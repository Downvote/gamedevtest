--!strict
-- Random Bakery's accessories, ported whole (the request of 2026-11-20: "Port the entire character customization menu
-- from the bakery game to this game, such accessory colors and other features, along with the accessories it has"):
-- hats, face pieces, things worn on the back, round the neck and in the right hand (Data/Cosmetics pieces with a
-- `kind`). Pure geometry through an Api that Models/WearModels binds: it draws every part in the bakery's own body
-- space, below, and WearModels fits each bone's parts onto the founder's smaller head, body and hands
-- (docs/ARCHITECTURE.md 6). The bakery's body (studs):
--   feet at y 0, legs y 0..1, torso (ROOT) x -0.75..0.75, y 1..2.5, z -0.5..0.5; arms at x +-1 (0.5 wide), y 1.375 ..
--   2.375, hands (y 1.125..1.375) at x +-1; head (HEAD) a 2-stud cube centred (0, 3.5, 0): y 2.5..4.5, x -1..1,
--   z -1..1; the front is +Z. Eyes 0.25 x 0.5 at (+-0.45, 3.4, 1), the mouth at (0, 2.85, 1). An uncovered hair cap
--   reaches y 4.75 (`bald`: no hair, the head top is 4.5); a covering hat's lower edge is its piece's `bottom`.
-- Each kind is drawn in its piece's two palette keys (`color` the main one, `accent` the second; a few neutral keys,
-- white / ink / black, for eyes, glints and seams), after the look's tint (Data/Looks.tinted). Hats that cover the
-- hair are built up from their `bottom` (kept in step with Data/Cosmetics); the others sit on the hair cap. Face
-- pieces lie on the face (z 1.0 .. 1.2) and leave the eyes showing unless they are glasses or a visor. Neck pieces
-- hang below the chin; back pieces hang behind the torso's back (z -0.5); held things are in the right hand (ARM_R,
-- the fist at (1, 1.25, 0)), tilted forward out of the arm's way so they read from the front-right camera.
--
-- Animation (the dearest pieces, the reward and event looks): Api.anim(from, frames) gives the parts added since
-- `from` (Api.count) a loop of frames, each a move in body space applied to their rest CFrames (a turn about a wing's
-- root, a spin about an axis, a step along a path); CharacterModels steps them 7 a second, each part through its own
-- list; a second anim on a part comes after the first. A part leaves the picture by moving inside a solid part of
-- its own bone (the head, the torso, the arm); still pictures show the rest pose (a part seen only on some frames, like
-- a flare or a bubble that pops, is drawn out of sight and brought out on its frames: REWARD.showF).
--
-- API
--   AccessoryModels.build(api, slot, kind, color, accent, ctx): boolean   draws `kind`; false when it has no model
--   AccessoryModels.KINDS: { [string]: string }                             kind -> slot, every kind drawn here
--   AccessoryModels.grip(kind): CFrame                                      a held piece's frame (the fist at its
--                                                                           origin; WearModels turns it about x)
export type Api = {
	add: (bone: number, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: string, rot: CFrame?, shape: string?, name: string?) -> (),
	ball: (bone: number, d: number, x: number, y: number, z: number, color: string, name: string?) -> (),
	cyl: (bone: number, d: number, h: number, x: number, y: number, z: number, color: string, name: string?) -> (),
	glow: () -> (), -- the part added last turns Neon
	count: () -> number, -- the parts added so far (where a moving group starts)
	anim: (from: number, frames: { CFrame }) -> (), -- every part added after `from` loops through `frames` (see Animation)
	HEAD: number,
	ROOT: number,
	ARM_R: number,
	ARM_L: number,
}
-- hair: the hair colour; bald: no hair (the head top is 4.5); skin; head: the hat is the head (the Pumpkin Head's
-- jack-o'-lantern, wider than the head, or the Headless flame), so a piece beside the head sits further out
export type Ctx = { hair: string, bald: boolean, skin: string, head: boolean? }
type Draw = (api: Api, c: string, a: string, ctx: Ctx) -> ()

local AccessoryModels = {}

AccessoryModels.KINDS = {} :: { [string]: string }

local PI = math.pi
local sin, cos = math.sin, math.cos
local ANG = CFrame.Angles
-- a Cylinder part runs along its X axis: FRONT turns it to face the front (a disc in the XY plane), UPRIGHT stands it up
local FRONT = ANG(0, PI / 2, 0)
local UPRIGHT = ANG(0, 0, PI / 2)
local DIAMOND = ANG(0, 0, PI / 4)

------------------------------------------------------------------ helpers

-- the hair cap's top (a hat that does not cover the hair sits on it)
local function capTop(ctx: Ctx): number
	return if ctx.bald then 4.5 else 4.75
end

-- a part placed in frame F: offset (dx, dy, dz), then turned by rot
local function fput(api: Api, bone: number, F: CFrame, sx: number, sy: number, sz: number, dx: number, dy: number, dz: number, color: string, rot: CFrame?, shape: string?)
	local cf = F * CFrame.new(dx, dy, dz)
	if rot then
		cf *= rot
	end
	api.add(bone, sx, sy, sz, cf.X, cf.Y, cf.Z, color, cf.Rotation, shape)
end

local function fball(api: Api, bone: number, F: CFrame, d: number, dx: number, dy: number, dz: number, color: string)
	local p = F * CFrame.new(dx, dy, dz)
	api.ball(bone, d, p.X, p.Y, p.Z, color)
end

-- a cylinder d across and h long along F's Y axis, centred s along it
local function fcyl(api: Api, bone: number, F: CFrame, d: number, h: number, s: number, color: string, dx: number?, dz: number?)
	fput(api, bone, F, h, d, d, dx or 0, s, dz or 0, color, UPRIGHT, "Cylinder")
end

-- a disc d across and t thick facing F's Z
local function fdisc(api: Api, bone: number, F: CFrame, d: number, t: number, dx: number, dy: number, dz: number, color: string)
	fput(api, bone, F, t, d, d, dx, dy, dz, color, FRONT, "Cylinder")
end

-- a disc facing the front
local function disc(api: Api, bone: number, d: number, t: number, x: number, y: number, z: number, color: string)
	api.add(bone, t, d, d, x, y, z, color, FRONT, "Cylinder")
end

-- a stick `len` long from (x0, y0) in F's XY plane, leaning `lean` radians off F's Y toward its +X
local function frod(api: Api, bone: number, F: CFrame, x0: number, y0: number, z: number, len: number, lean: number, w: number, d: number, color: string)
	fput(api, bone, F, w, len, d, x0 + sin(lean) * len / 2, y0 + cos(lean) * len / 2, z, color, ANG(0, 0, -lean))
end

local function rod(api: Api, bone: number, x0: number, y0: number, z: number, len: number, lean: number, w: number, d: number, color: string)
	frod(api, bone, CFrame.identity, x0, y0, z, len, lean, w, d, color)
end

-- a square-section stick w thick from (x1, y1, z1) to (x2, y2, z2): strings, chains, straps
local function link(api: Api, bone: number, x1: number, y1: number, z1: number, x2: number, y2: number, z2: number, w: number, color: string)
	local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-3 then
		return
	end
	local rot = ANG(math.atan2(dz / len, dy / len), 0, -math.asin(math.clamp(dx / len, -1, 1)))
	api.add(bone, w, len, w, (x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2, color, rot)
end

-- a five-pointed star facing F's Z: a round middle (in `core`, else the colour) and five squares turned corner out;
-- r is the points' distance from the middle, the tips reach about 1.8 r; `lit`: all of it glows
local function star(api: Api, bone: number, F: CFrame, r: number, t: number, color: string, core: string?, lit: boolean?)
	fdisc(api, bone, F, r * 1.7, t * 1.1, 0, 0, 0, core or color)
	if lit then
		api.glow()
	end
	for k = 0, 4 do
		local ang = k * 2 * PI / 5
		fput(api, bone, F, r * 1.1, r * 1.1, t, sin(ang) * r, cos(ang) * r, 0, color, ANG(0, 0, PI / 4 - ang))
		if lit then
			api.glow()
		end
	end
end

-- a heart facing F's Z, s across: two round lobes over a square turned corner down
local function heart(api: Api, bone: number, F: CFrame, s: number, t: number, color: string)
	fdisc(api, bone, F, s * 0.55, t, -s * 0.21, s * 0.09, 0, color)
	fdisc(api, bone, F, s * 0.55, t, s * 0.21, s * 0.09, 0, color)
	fput(api, bone, F, s * 0.55, s * 0.55, t, 0, -s * 0.125, 0, color, DIAMOND)
end

-- a wing's frame on the back: its root by the spine, x running out (mirrored by sx) and turning back, y up
local function wingFrame(sx: number, y: number, yaw: number): CFrame
	return CFrame.new(sx * 0.25, y, -0.62) * ANG(0, sx * yaw, 0)
end

-- a panel in wing frame W at (lx, ly) (lx mirrored by sx) turned `turn` (its top toward the root for turn > 0)
local function wpanel(api: Api, W: CFrame, sx: number, lx: number, ly: number, w: number, h: number, t: number, turn: number, color: string)
	fput(api, api.ROOT, W, w, h, t, sx * lx, ly, 0, color, ANG(0, 0, sx * turn))
end

local function wdisc(api: Api, W: CFrame, sx: number, lx: number, ly: number, d: number, t: number, color: string)
	fdisc(api, api.ROOT, W, d, t, sx * lx, ly, 0, color)
end

-- the right hand's frame for a held thing: the fist at its origin, y along the handle, tilted forward and a little out
local GRIP = CFrame.new(1.02, 1.25, 0.28) * ANG(0.45, 0, -0.15)
-- turned a little more toward the camera, for flat things (a blade, a lollipop, a star)
local GRIP_FACE = GRIP * ANG(0, 0.6, 0)
-- The customization screen's Hand tab shows the wearer turned 80 degrees past the world's view (UI/FounderUI), where
-- a flat thing facing the world's camera is seen edge on (a lollipop was a sliver there). Turned half way back about
-- the vertical, it faces between the two and reads in both.
local function faceBoth(F: CFrame): CFrame
	return CFrame.new(F.Position) * ANG(0, -0.7, 0) * F.Rotation
end

-- shoulder straps on the front, over the apron (backpacks)
local function straps(api: Api, color: string)
	for _, sx in { -1, 1 } do
		api.add(api.ROOT, 0.2, 0.75, 0.1, sx * 0.48, 2.1, 0.72, color)
		api.add(api.ROOT, 0.2, 0.12, 1.25, sx * 0.48, 2.44, 0.05, color)
	end
end

------------------------------------------------------------------ hats

local HAT: { [string]: Draw } = {}

-- eight points round a band (three in front), a low velvet cushion in the accent and an orb, a gem and pearls
HAT.crown = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	api.add(H, 1.7, 0.36, 1.7, 0, t + 0.13, -0.05, c)
	api.cyl(H, 1.3, 0.22, 0, t + 0.36, -0.05, a)
	api.ball(H, 0.22, 0, t + 0.54, -0.05, c)
	local py = t + 0.31
	for _, x in { -0.55, 0, 0.55 } do
		api.add(H, 0.48, 0.48, 0.14, x, py, 0.78, c, DIAMOND)
		api.add(H, 0.48, 0.48, 0.14, x, py, -0.88, c, DIAMOND)
	end
	for _, sx in { -1, 1 } do
		api.add(H, 0.14, 0.48, 0.48, sx * 0.78, py, -0.05, c, ANG(PI / 4, 0, 0))
		api.ball(H, 0.12, sx * 0.48, t + 0.13, 0.83, "white")
	end
	api.add(H, 0.24, 0.24, 0.12, 0, t + 0.13, 0.82, a, DIAMOND)
end

-- the Chewy track's Gummy Crown (it was the crown in purple): a band of gummy candy (the colour) with eight tall
-- rounded gummy points in place of sharp ones (the accent and the colour by turns, three in front), glowing a little
-- like see-through candy, each with a white shine, and an orange gummy bear sitting on top in the middle
HAT.gummy_crown = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	api.add(H, 1.72, 0.32, 1.72, 0, t + 0.11, -0.05, c)
	local DROPS = { { -0.55, 0.8 }, { 0, 0.8 }, { 0.55, 0.8 }, { 0.8, -0.05 }, { 0.55, -0.9 }, { 0, -0.9 }, { -0.55, -0.9 }, { -0.8, -0.05 } }
	for i, d in DROPS do
		local col = if i % 2 == 1 then a else c
		api.cyl(H, 0.42, 0.36, d[1], t + 0.4, d[2], col)
		api.glow()
		api.ball(H, 0.42, d[1], t + 0.58, d[2], col)
		api.glow()
		api.add(H, 0.08, 0.16, 0.08, d[1] - 0.1, t + 0.56, d[2] + 0.15, "white")
	end
	-- the bear: body, head, ears, paws, feet, eyes, a shine
	local B = "orange"
	api.ball(H, 0.56, 0, t + 0.5, -0.05, B)
	api.glow()
	api.ball(H, 0.46, 0, t + 0.92, 0, B)
	api.glow()
	for _, sx in { -1, 1 } do
		api.ball(H, 0.2, sx * 0.17, t + 1.14, 0, B)
		api.ball(H, 0.2, sx * 0.27, t + 0.58, 0.14, B)
		api.ball(H, 0.22, sx * 0.15, t + 0.3, 0.2, B)
	end
	api.add(H, 0.08, 0.08, 0.08, -0.08, t + 0.97, 0.23, "ink")
	api.add(H, 0.08, 0.08, 0.08, 0.1, t + 0.97, 0.23, "ink")
	api.add(H, 0.1, 0.1, 0.1, -0.14, t + 1.06, 0.18, "white")
end

-- the Crunchy track's Brittle Crown (it was the crown in brown): a band of nut brittle with jagged shards of it standing
-- up round it at odd heights and leans in place of points (the colour and the accent by turns, each with a broken
-- tip), nuts set in the band and the shards, no cushion
HAT.brittle_crown = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	api.add(H, 1.72, 0.3, 1.72, 0, t + 0.1, -0.05, c)
	-- { x, z of its foot on the band, height, width, lean out, tilt to one side, tip: the broken top's turn }
	local SHARDS: { { number } } = {
		{ -0.55, 0.8, 0.7, 0.42, 0.28, 0.22, 0.5 },
		{ 0.02, 0.82, 0.95, 0.5, 0.14, -0.12, -0.4 },
		{ 0.58, 0.8, 0.62, 0.4, 0.3, -0.3, 0.6 },
		{ 0.82, 0.32, 0.82, 0.44, 0.22, 0.18, -0.5 },
		{ 0.82, -0.45, 0.6, 0.4, 0.34, -0.2, 0.4 },
		{ 0.4, -0.9, 0.85, 0.46, 0.2, 0.25, -0.6 },
		{ -0.35, -0.9, 0.66, 0.42, 0.3, -0.2, 0.5 },
		{ -0.82, -0.4, 0.9, 0.46, 0.16, 0.15, -0.4 },
		{ -0.82, 0.32, 0.64, 0.4, 0.3, -0.25, 0.55 },
	}
	for i, s in SHARDS do
		local x, z, h, w = s[1], s[2], s[3], s[4]
		local zc = z + 0.05
		local out = math.atan2(x, zc)
		local F = CFrame.new(x, t + 0.12, z) * ANG(0, out, 0) * ANG(s[5], 0, s[6])
		local col = if i % 2 == 1 then c else a
		fput(api, H, F, w, h * 0.7, 0.12, 0, h * 0.35, 0, col)
		fput(api, H, F, w * 0.62, w * 0.62, 0.12, w * 0.08, h * 0.7, 0, col, ANG(0, 0, PI / 4 + s[7]))
		if i % 3 ~= 2 then
			fput(api, H, F, 0.13, 0.11, 0.06, -w * 0.15, h * 0.3, 0.08, if i % 2 == 1 then "chocolate" else "floor_a", ANG(0, 0, 0.5))
		end
	end
	local NUTS: { { x: number, z: number, col: string } } = {
		{ x = -0.6, z = 0.83, col = "chocolate" },
		{ x = 0.12, z = 0.83, col = "floor_a" },
		{ x = 0.83, z = 0.05, col = "chocolate" },
		{ x = 0.83, z = -0.6, col = "floor_a" },
	}
	for _, n in NUTS do
		local rot = if math.abs(n.z) > 0.8 then ANG(0, 0, 0.6) else ANG(0.6, 0, 0)
		api.add(H, 0.16, 0.12, 0.16, n.x, t + 0.12, n.z, n.col, rot)
	end
end

-- a band on the front of the hair rising to a tall jewelled spire, smaller diamonds stepping down each side, its front
-- tipped back over the hair so it faces up toward the camera (bold enough to read from above in the customization screen's Hat
-- tab, where the slimmer upright one was a thin line)
HAT.tiara = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local T = CFrame.new(0, t + 0.02, 0.92) * ANG(-0.5, 0, 0)
	fput(api, H, T, 1.7, 0.24, 0.2, 0, 0.1, 0, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.8, 0.22, 0.2, sx * 0.98, t + 0.08, 0.56, c, ANG(0, sx * 1.17, 0))
		fput(api, H, T, 0.44, 0.44, 0.14, sx * 0.46, 0.32, 0, c, DIAMOND)
		fput(api, H, T, 0.28, 0.28, 0.14, sx * 0.8, 0.22, 0, c, DIAMOND)
		fball(api, H, T, 0.18, sx * 0.46, 0.34, 0.09, a)
		api.glow()
	end
	fput(api, H, T, 0.72, 0.72, 0.14, 0, 0.52, 0, c, DIAMOND)
	fput(api, H, T, 0.34, 0.34, 0.14, 0, 1.08, 0, c, DIAMOND)
	fput(api, H, T, 0.34, 0.34, 0.16, 0, 0.52, 0.05, a, DIAMOND)
	api.glow()
end

-- six big flowers round the hair (a yellow middle on top of each), leaves between
HAT.flower_crown = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local mid = "yellow"
	local y = t - 0.02
	for k = 0, 5 do
		local ang = k * PI / 3
		api.ball(H, 0.56, cos(ang) * 1.0, y, -0.05 + sin(ang) * 1.0, c)
		api.ball(H, 0.24, cos(ang) * 1.1, y + 0.17, -0.05 + sin(ang) * 1.1, mid)
	end
	for _, k in { 0.5, 1.5, 2.5 } do
		local ang = k * PI / 3
		api.add(H, 0.28, 0.28, 0.1, cos(ang) * 1.12, y - 0.04, -0.05 + sin(ang) * 1.12, a, ANG(0, PI / 2 - ang, 0) * DIAMOND)
	end
end

-- the Sunflower Crown (it was the flower crown in yellow): six flat sunflowers standing up round the hair, faces
-- turned out and tipped up a little, each a ring of pointed petals (the colour) round a big dark middle seeded lighter
-- and green behind (the accent, as the leaves between them are)
HAT.sunflower_crown = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	for k = 0, 5 do
		local ang = PI / 6 + k * PI / 3
		local x, z = cos(ang) * 1.0, -0.05 + sin(ang) * 1.0
		local S = CFrame.new(x, t + 0.32, z) * ANG(0, math.atan2(x, z + 0.05), 0) * ANG(-0.65, 0, 0)
		fdisc(api, H, S, 0.86, 0.1, 0, 0, 0, c)
		fdisc(api, H, S, 0.7, 0.08, 0, 0, -0.07, a)
		for p = 0, 7 do
			local q = p * PI / 4
			fput(api, H, S, 0.26, 0.26, 0.08, cos(q) * 0.46, sin(q) * 0.46, 0, c, ANG(0, 0, q + PI / 4))
		end
		fdisc(api, H, S, 0.48, 0.12, 0, 0, 0.04, "choco_dark")
		fput(api, H, S, 0.1, 0.1, 0.06, -0.1, 0.07, 0.1, "chocolate")
		fput(api, H, S, 0.1, 0.1, 0.06, 0.1, -0.06, 0.1, "chocolate")
		local la = ang + PI / 6
		api.add(H, 0.34, 0.34, 0.1, cos(la) * 1.1, t + 0.02, -0.05 + sin(la) * 1.1, a, ANG(0, PI / 2 - la, 0) * DIAMOND)
	end
end

-- bottom 4.5: a narrow brim, a tall crown with a band in the accent, a lip round the top, a shine on its near side
HAT.top_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	api.cyl(H, 2.7, 0.15, 0, 4.575, -0.05, c)
	api.cyl(H, 1.75, 1.35, 0, 5.325, -0.05, c)
	api.cyl(H, 1.8, 0.28, 0, 4.8, -0.05, a)
	api.cyl(H, 1.85, 0.12, 0, 5.98, -0.05, c)
	api.add(H, 0.14, 0.8, 0.1, 0.62, 5.5, 0.57, "white", ANG(0, PI / 4, 0))
end

-- a striped cone leaning a little to one side on a frill, a pompom on the tip
HAT.party_hat = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local F = CFrame.new(0.1, t - 0.02, 0.05) * ANG(0, 0, -0.18)
	fcyl(api, H, F, 1.3, 0.12, 0.06, a)
	for i, d in { 1.15, 0.9, 0.66, 0.44, 0.24 } do
		fcyl(api, H, F, d, 0.3, 0.27 + (i - 1) * 0.3, if i % 2 == 1 then c else a)
	end
	fball(api, H, F, 0.36, 0, 1.72, 0, a)
end

-- bottom 4.4: a wide brim curled up at the sides, a round crown pinched into two ridges, a band and a gold badge
HAT.cowboy_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 2.8, 0.15, 2.7, 0, 4.475, -0.05, c)
	api.cyl(H, 1.75, 0.75, 0, 4.925, -0.1, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.45, 0.15, 2.5, sx * 1.565, 4.63, -0.05, c, ANG(0, 0, sx * 0.75))
		api.add(H, 1.3, 0.42, 0.42, sx * 0.3, 5.28, -0.12, c, FRONT, "Cylinder")
	end
	api.cyl(H, 1.8, 0.2, 0, 4.66, -0.1, a)
	api.add(H, 0.24, 0.24, 0.12, 0, 4.66, 0.82, "gold", DIAMOND)
end

-- bottom 4.4: a cap under a tall bicorne crest swept down at the ends, trimmed in the accent, skull and crossbones
HAT.pirate_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 2.35, 0.45, 2.45, 0, 4.625, -0.05, c)
	api.add(H, 1.7, 0.95, 0.5, 0, 5.25, 0, c)
	api.add(H, 1.72, 0.12, 0.54, 0, 5.73, 0, a)
	for _, sx in { -1, 1 } do
		local W = CFrame.new(sx * 1.15, 5.0, 0) * ANG(0, 0, -sx * 0.45)
		fput(api, H, W, 1.0, 0.6, 0.48, 0, 0, 0, c)
		fput(api, H, W, 1.02, 0.12, 0.52, 0, 0.33, 0, a)
	end
	api.add(H, 0.62, 0.12, 0.08, 0, 5.12, 0.28, "white", ANG(0, 0, PI / 4))
	api.add(H, 0.62, 0.12, 0.08, 0, 5.12, 0.28, "white", ANG(0, 0, -PI / 4))
	api.add(H, 0.36, 0.32, 0.1, 0, 5.27, 0.3, "white")
	api.add(H, 0.1, 0.1, 0.1, -0.08, 5.28, 0.35, "ink")
	api.add(H, 0.1, 0.1, 0.1, 0.08, 5.28, 0.35, "ink")
end

-- bottom 4.4: a wide brim, a band in the accent, a cone that bends over at the top, little stars in the accent
HAT.wizard_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	api.cyl(H, 3.0, 0.15, 0, 4.475, -0.05, c)
	api.cyl(H, 1.95, 0.45, 0, 4.775, -0.05, c)
	api.cyl(H, 2.0, 0.18, 0, 4.64, -0.05, a)
	api.cyl(H, 1.55, 0.45, 0, 5.2, -0.05, c)
	api.cyl(H, 1.15, 0.4, 0, 5.6, -0.05, c)
	local F = CFrame.new(0, 5.78, -0.05) * ANG(0, 0, 0.4)
	fcyl(api, H, F, 0.8, 0.4, 0.18, c)
	fcyl(api, H, F, 0.5, 0.36, 0.53, c)
	local F2 = F * CFrame.new(0, 0.7, 0) * ANG(0, 0, 0.55)
	fcyl(api, H, F2, 0.28, 0.32, 0.14, c)
	fball(api, H, F2, 0.18, 0, 0.34, 0, a)
	api.glow()
	api.add(H, 0.2, 0.2, 0.08, 0.45, 4.85, 0.84, a, DIAMOND)
	api.add(H, 0.18, 0.18, 0.08, -0.3, 5.26, 0.69, a, DIAMOND)
	api.add(H, 0.14, 0.14, 0.08, 0.2, 5.62, 0.51, a, DIAMOND)
end

-- a glowing ring floating over the head, tipped toward the camera, two sparkles beside it
HAT.halo = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local F = CFrame.new(0, t + 0.62, -0.05) * ANG(0.3, 0, 0)
	local r, n = 0.72, 8
	local len = 2 * r * math.tan(PI / n) + 0.1
	for k = 0, n - 1 do
		local ang = k * 2 * PI / n
		fput(api, H, F, len, 0.12, 0.16, cos(ang) * r, 0, sin(ang) * r, c, ANG(0, PI / 2 - ang, 0))
		api.glow()
	end
	api.add(H, 0.14, 0.14, 0.1, -0.95, t + 0.95, 0.2, a, DIAMOND)
	api.glow()
	api.add(H, 0.12, 0.12, 0.1, 0.98, t + 0.45, 0.3, a, DIAMOND)
	api.glow()
end

-- bottom 4.25: a cap in panels (the front and a stripe over the top in the accent), a peak, a two-blade propeller
HAT.propeller_cap = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 2.35, 0.55, 2.45, 0, 4.525, -0.05, c)
	api.add(H, 1.95, 0.25, 2.0, 0, 4.925, -0.05, c)
	api.add(H, 0.6, 0.57, 0.1, 0, 4.525, 1.18, a)
	api.add(H, 0.6, 0.27, 2.02, 0, 4.925, -0.05, a)
	api.add(H, 1.7, 0.12, 0.65, 0, 4.31, 1.45, c)
	api.cyl(H, 0.14, 0.3, 0, 5.2, -0.05, a)
	api.ball(H, 0.26, 0, 5.4, -0.05, c)
	local F = CFrame.new(0, 5.4, -0.05) * ANG(0, 0.5, 0)
	fput(api, H, F, 0.95, 0.12, 0.34, 0.55, 0, 0, a, ANG(0.35, 0, 0))
	fput(api, H, F, 0.95, 0.12, 0.34, -0.55, 0, 0, "berry_red", ANG(-0.35, 0, 0))
end

-- Bear Ears: two round ears on top of the head, the inside of each a flat disc in the accent (Mouse Ears, which shared
-- this model, have big flat ones of their own)
HAT.bear_ears = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	for _, sx in { -1, 1 } do
		api.ball(H, 0.92, sx * 0.8, t + 0.24, -0.1, c)
		disc(api, H, 0.54, 0.1, sx * 0.8, t + 0.22, 0.32, a)
	end
end

-- Mouse Ears: two big flat round ears standing up on top of the head and leaning out a little, the inside of each a
-- disc in the accent (a cartoon mouse's)
HAT.mouse_ears = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	for _, sx in { -1, 1 } do
		local F = CFrame.new(sx * 0.66, t + 0.52, -0.2) * ANG(0, 0, -sx * 0.22)
		fdisc(api, H, F, 1.2, 0.16, 0, 0, 0, c)
		fdisc(api, H, F, 0.76, 0.1, 0, -0.03, 0.09, a)
	end
end

-- two tall pointed ears (stepped triangles) leaning out, the inside in the accent
HAT.fox_ears = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	for _, sx in { -1, 1 } do
		local F = CFrame.new(sx * 0.6, t - 0.1, -0.1) * ANG(0, sx * 0.25, -sx * 0.22)
		for i, w in { 0.9, 0.64, 0.4, 0.18 } do
			fput(api, H, F, w, 0.26, 0.3, 0, 0.13 + (i - 1) * 0.25, 0, c)
		end
		fput(api, H, F, 0.5, 0.25, 0.1, 0, 0.3, 0.16, a)
		fput(api, H, F, 0.26, 0.25, 0.1, 0, 0.55, 0.16, a)
	end
end

-- a branching antler on each side, the burr at its foot in the accent
HAT.antlers = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local z = -0.05
	for _, sx in { -1, 1 } do
		local bx, by, lean, len = sx * 0.6, t - 0.02, sx * 0.35, 1.2
		local function on(f: number): (number, number)
			return bx + sin(lean) * len * f, by + cos(lean) * len * f
		end
		rod(api, H, bx, by, z, len, lean, 0.22, 0.22, c)
		local x1, y1 = on(0.32)
		rod(api, H, x1, y1, z, 0.58, sx * 1.05, 0.18, 0.18, c)
		local x2, y2 = on(0.68)
		rod(api, H, x2, y2, z, 0.52, sx * 0.72, 0.18, 0.18, c)
		local x3, y3 = on(0.8)
		rod(api, H, x3, y3, z, 0.46, -sx * 0.5, 0.16, 0.16, c)
		api.ball(H, 0.32, bx, t + 0.04, z, a)
	end
end

-- a tall spiral horn on the forehead, leaning forward, ringed in the accent
HAT.unicorn_horn = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local F = CFrame.new(0, t - 0.05, 0.45) * ANG(0.3, 0, 0)
	fcyl(api, H, F, 0.7, 0.4, 0.2, c)
	fcyl(api, H, F, 0.74, 0.12, 0.45, a)
	fcyl(api, H, F, 0.54, 0.38, 0.68, c)
	fcyl(api, H, F, 0.58, 0.12, 0.92, a)
	fcyl(api, H, F, 0.38, 0.36, 1.14, c)
	fcyl(api, H, F, 0.42, 0.12, 1.37, a)
	fcyl(api, H, F, 0.22, 0.34, 1.57, c)
	fball(api, H, F, 0.15, 0, 1.77, 0, c)
end

-- a band over the hair down to a round cup on each ear, the caps in the accent with a glowing dot
HAT.headphones = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local cy = 3.45
	api.add(H, 2.3, 0.2, 0.28, 0, t + 0.15, 0, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.3, 0.8, 0.8, sx * 1.2, cy, 0, c, nil, "Cylinder")
		api.add(H, 0.14, 0.58, 0.58, sx * 1.4, cy, 0, a, nil, "Cylinder")
		api.add(H, 0.14, 0.2, 0.2, sx * 1.48, cy, 0, "white", nil, "Cylinder")
		api.glow()
		local y0, y1 = cy + 0.3, t + 0.25
		api.add(H, 0.18, y1 - y0, 0.26, sx * 1.22, (y0 + y1) / 2, 0, c)
	end
end

-- bottom 4.45: a wide floppy brim, a low crown, a ribbon in the accent with a flower on it
HAT.sun_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	api.cyl(H, 3.3, 0.12, 0, 4.51, -0.05, c)
	api.cyl(H, 1.9, 0.65, 0, 4.895, -0.05, c)
	api.cyl(H, 1.6, 0.14, 0, 5.27, -0.05, c)
	api.cyl(H, 1.95, 0.2, 0, 4.7, -0.05, a)
	local dx, dz = cos(0.96), sin(0.96)
	api.ball(H, 0.4, dx * 1.02, 4.72, -0.05 + dz * 1.02, a)
	api.ball(H, 0.16, dx * 1.2, 4.75, -0.05 + dz * 1.2, "white")
	for _, ang in { 0.62, 1.32 } do
		api.add(H, 0.22, 0.22, 0.1, cos(ang) * 1.02, 4.66, -0.05 + sin(ang) * 1.02, "green", ANG(0, PI / 2 - ang, 0) * DIAMOND)
	end
end

-- bottom 4.1: a turned-up cuff in the accent, a striped body, a big pompom
HAT.pompom_beanie = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 2.45, 0.45, 2.5, 0, 4.325, -0.05, a)
	api.add(H, 2.25, 0.65, 2.3, 0, 4.875, -0.05, c)
	api.add(H, 2.27, 0.14, 2.32, 0, 4.85, -0.05, a)
	api.add(H, 1.7, 0.25, 1.75, 0, 5.325, -0.05, c)
	api.ball(H, 0.72, 0, 5.7, -0.05, a)
end

-- the Soft track's Cloud Beanie (bottom 4.1; it was the pompom beanie in white): a knitted cuff in the accent under a
-- lumpy white cloud of a crown, puffs bulging out all round it and piled on top, a little puff on the very top
HAT.cloud_beanie = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 2.45, 0.45, 2.5, 0, 4.325, -0.05, a)
	api.add(H, 2.1, 0.5, 2.15, 0, 4.78, -0.05, c)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			api.ball(H, 1.05, sx * 0.72, 4.84, -0.05 + sz * 0.72, c)
		end
		api.ball(H, 0.9, sx * 1.12, 4.7, -0.05, c)
		api.ball(H, 0.9, 0, 4.7, -0.05 + sx * 1.12, c)
	end
	api.ball(H, 1.4, 0, 5.18, -0.05, c)
	api.ball(H, 0.95, -0.42, 5.4, 0.22, c)
	api.ball(H, 0.9, 0.46, 5.44, -0.32, c)
	api.ball(H, 0.6, 0.05, 5.86, -0.02, c)
end

-- bottom 4.2: a round steel dome on a rim, a nose guard, a big curved horn in the accent on each side
HAT.viking_helmet = function(api, c, a, _ctx)
	local H = api.HEAD
	api.cyl(H, 2.5, 0.3, 0, 4.35, -0.05, c)
	api.cyl(H, 2.3, 0.35, 0, 4.675, -0.05, c)
	api.cyl(H, 2.0, 0.25, 0, 4.975, -0.05, c)
	api.cyl(H, 1.45, 0.2, 0, 5.2, -0.05, c)
	api.add(H, 0.25, 0.7, 0.12, 0, 3.95, 1.18, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.22, 0.46, 0.46, sx * 1.27, 4.6, -0.05, c)
		api.ball(H, 0.5, sx * 1.47, 4.68, -0.05, a)
		api.ball(H, 0.42, sx * 1.7, 4.92, -0.05, a)
		api.ball(H, 0.32, sx * 1.82, 5.2, -0.05, a)
		api.ball(H, 0.22, sx * 1.84, 5.44, -0.05, a)
	end
end

-- bottom 4.3: a round shell with a little rim, a peak in front, a ridge over the top and a badge in the accent
HAT.hard_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	api.cyl(H, 2.6, 0.12, 0, 4.36, -0.05, c)
	api.cyl(H, 2.3, 0.45, 0, 4.64, -0.05, c)
	api.cyl(H, 2.0, 0.25, 0, 4.99, -0.05, c)
	api.cyl(H, 1.45, 0.14, 0, 5.18, -0.05, c)
	api.add(H, 1.6, 0.12, 0.6, 0, 4.36, 1.42, c)
	api.add(H, 0.36, 0.3, 2.1, 0, 5.15, -0.05, a)
	api.add(H, 0.5, 0.3, 0.1, 0, 4.62, 1.14, a)
end

-- bottom 4.35: a skull cap under a square board (turned corner to the front), a button and a tassel in the accent
HAT.graduation_cap = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 2.3, 0.5, 2.35, 0, 4.6, -0.05, c)
	api.add(H, 2.3, 0.12, 2.3, 0, 4.91, -0.05, c, ANG(0, PI / 4, 0))
	api.cyl(H, 0.26, 0.1, 0, 5.02, -0.05, a)
	api.add(H, 1.55, 0.1, 0.1, 0.775, 5.02, -0.05, a)
	api.add(H, 0.12, 0.45, 0.12, 1.55, 4.75, -0.05, a)
	api.add(H, 0.22, 0.3, 0.22, 1.55, 4.42, -0.05, a)
end

-- bottom 4.15: a fluffy cuff in the accent, a soft cone flopping over to one side, a pompom hanging off its tip
HAT.santa_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 2.5, 0.5, 2.55, 0, 4.4, -0.05, a)
	api.add(H, 2.2, 0.5, 2.25, 0, 4.9, -0.05, c)
	api.add(H, 1.75, 0.35, 1.8, 0.05, 5.3, -0.05, c)
	api.ball(H, 1.3, 0.12, 5.5, -0.05, c)
	api.ball(H, 0.95, 0.45, 5.78, -0.05, c)
	api.ball(H, 0.7, 0.82, 5.84, -0.05, c)
	api.ball(H, 0.5, 1.12, 5.7, -0.05, c)
	api.ball(H, 0.36, 1.3, 5.48, -0.05, c)
	api.ball(H, 0.56, 1.38, 5.2, -0.05, a)
end

-- bottom 4.15: a green cap with two bulging frog eyes on top, a smile and pink cheeks on its front
HAT.frog_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 2.45, 0.75, 2.5, 0, 4.525, -0.05, c)
	api.add(H, 2.1, 0.25, 2.15, 0, 5.025, -0.05, c)
	for _, sx in { -1, 1 } do
		api.ball(H, 0.75, sx * 0.55, 5.18, 0.45, c)
		api.ball(H, 0.5, sx * 0.55, 5.26, 0.66, a)
		api.ball(H, 0.24, sx * 0.55, 5.28, 0.88, "black")
		api.add(H, 0.3, 0.16, 0.1, sx * 0.78, 4.42, 1.21, "pink")
		api.add(H, 0.1, 0.14, 0.1, sx * 0.42, 4.4, 1.22, "ink")
	end
	api.add(H, 0.74, 0.1, 0.1, 0, 4.34, 1.22, "ink")
end

-- a thin band over the hair, a big polka-dot bow on it at the front of one side
HAT.bow_headband = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local side = if ctx.bald then 1.06 else 1.18
	api.add(H, side * 2, 0.14, 0.3, 0, t + 0.04, 0.3, c)
	local bx, by, bz = 0.48, t + 0.3, 0.5
	for _, sx in { -1, 1 } do
		api.add(H, 0.14, 0.75, 0.3, sx * side, t - 0.34, 0.3, c)
		api.add(H, 0.6, 0.5, 0.22, bx + sx * 0.33, by + 0.05, bz, c, ANG(0, 0, sx * 0.3))
		api.add(H, 0.12, 0.12, 0.1, bx + sx * 0.38, by + 0.08, bz + 0.13, a)
		api.add(H, 0.16, 0.38, 0.14, bx + sx * 0.14, by - 0.27, bz, c, ANG(0, 0, sx * 0.35))
	end
	api.add(H, 0.24, 0.28, 0.28, bx, by, bz + 0.02, c)
end

-- a terry band round the forehead (over the fringe), a stripe in the accent
HAT.sweatband = function(api, c, a, ctx)
	local H = api.HEAD
	local y = 4.0
	local zf, zb, side = 1.2, -1.31, 1.24
	if ctx.bald then
		zf, zb, side = 1.06, -1.06, 1.06
	end
	api.add(H, side * 2, 0.38, 0.12, 0, y, zf, c)
	api.add(H, side * 2 + 0.02, 0.12, 0.14, 0, y, zf, a)
	api.add(H, side * 2, 0.38, 0.12, 0, y, zb, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.12, 0.38, zf - zb, sx * side, y, (zf + zb) / 2, c)
		api.add(H, 0.14, 0.12, zf - zb + 0.02, sx * side, y, (zf + zb) / 2, a)
	end
end

-- a pair of cherries clipped at each temple, green stems and a leaf
HAT.cherry_clips = function(api, c, a, ctx)
	local H = api.HEAD
	local z = if ctx.bald then 1.08 else 1.22
	for _, sx in { -1, 1 } do
		local x = sx * 0.72
		api.ball(H, 0.3, x - sx * 0.13, 3.98, z, c)
		api.ball(H, 0.3, x + sx * 0.12, 3.92, z + 0.02, c)
		link(api, H, x - sx * 0.13, 4.1, z, x + sx * 0.02, 4.36, z, 0.1, a)
		link(api, H, x + sx * 0.12, 4.04, z, x + sx * 0.02, 4.36, z, 0.1, a)
		api.add(H, 0.24, 0.12, 0.1, x + sx * 0.14, 4.38, z, a, ANG(0, 0, sx * 0.4))
	end
end

------------------------------------------------------------------ face

local FACE: { [string]: Draw } = {}

-- a gold rim and a lens round the right eye (behind the eye's front, so the eye shows), a chain to the cheek
FACE.monocle = function(api, c, a, _ctx)
	local H = api.HEAD
	disc(api, H, 0.74, 0.1, 0.45, 3.4, 1.03, c)
	disc(api, H, 0.56, 0.1, 0.45, 3.4, 1.05, a)
	api.add(H, 0.1, 0.1, 0.1, 0.24, 3.6, 1.11, "white")
	link(api, H, 0.7, 3.14, 1.06, 0.88, 2.85, 1.04, 0.1, c)
	link(api, H, 0.88, 2.85, 1.04, 1.05, 2.75, 0.75, 0.1, c)
end

-- the Barely Sweet track's Tea Monocle (it was the monocle in green): the rim (the colour) and lens round the right
-- eye with a tea leaf sprouting off its top, and in place of a chain a tea bag's white string down past the cheek to
-- its paper tag, a tea leaf printed on it
FACE.tea_monocle = function(api, c, a, _ctx)
	local H = api.HEAD
	disc(api, H, 0.74, 0.1, 0.45, 3.4, 1.03, c)
	disc(api, H, 0.56, 0.1, 0.45, 3.4, 1.05, a)
	api.add(H, 0.1, 0.1, 0.1, 0.24, 3.6, 1.11, "white")
	api.add(H, 0.3, 0.18, 0.1, 0.72, 3.84, 1.06, "grass", ANG(0, 0, 0.55))
	api.add(H, 0.08, 0.16, 0.1, 0.6, 3.74, 1.05, c, ANG(0, 0, -0.4))
	link(api, H, 0.7, 3.16, 1.07, 0.84, 2.84, 1.08, 0.07, "white")
	api.add(H, 0.36, 0.4, 0.08, 0.86, 2.66, 1.1, "white")
	api.add(H, 0.16, 0.18, 0.08, 0.86, 2.64, 1.14, c, DIAMOND)
end

-- a patch over the left eye, its strap across the forehead and round the sides
FACE.eyepatch = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 0.55, 0.55, 0.1, -0.45, 3.43, 1.14, c)
	api.add(H, 0.4, 0.12, 0.1, -0.45, 3.1, 1.14, c)
	link(api, H, -0.5, 3.62, 1.12, 1.05, 4.02, 1.1, 0.12, a)
	api.add(H, 0.1, 0.12, 1.0, -1.04, 3.3, 0.55, a, ANG(0.15, 0, 0))
	api.add(H, 0.1, 0.12, 1.0, 1.04, 3.98, 0.55, a, ANG(-0.15, 0, 0))
end

-- a five-pointed star round each eye, the dark middle the lens, a bridge between
FACE.star_glasses = function(api, c, a, _ctx)
	local H = api.HEAD
	for _, sx in { -1, 1 } do
		star(api, H, CFrame.new(sx * 0.45, 3.42, 1.15), 0.24, 0.1, c, a)
	end
	api.add(H, 0.2, 0.1, 0.1, 0, 3.5, 1.15, c)
end

-- a heart over each eye, a dark bridge and arms, a white glint on each
FACE.heart_glasses = function(api, c, a, _ctx)
	local H = api.HEAD
	for _, sx in { -1, 1 } do
		heart(api, H, CFrame.new(sx * 0.45, 3.42, 1.15), 0.68, 0.1, c)
		api.add(H, 0.1, 0.1, 0.1, sx * 0.45 - 0.14, 3.52, 1.21, "white")
		api.add(H, 0.1, 0.1, 0.95, sx * 1.04, 3.5, 0.6, a)
	end
	api.add(H, 0.26, 0.1, 0.1, 0, 3.52, 1.15, a)
end

-- the Sweet track's Sweetheart Glasses (they were the heart glasses in red): square frames (the colour) with tinted
-- lenses (the accent; the eyes show through), a little heart in the colour perched on each outer corner and one on
-- the bridge, a white shine on each lens, arms
FACE.sweetheart_glasses = function(api, c, a, _ctx)
	local H = api.HEAD
	for _, sx in { -1, 1 } do
		local x = sx * 0.45
		api.add(H, 0.78, 0.64, 0.1, x, 3.4, 1.03, c)
		api.add(H, 0.58, 0.46, 0.1, x, 3.4, 1.05, a)
		api.add(H, 0.1, 0.1, 0.1, x - 0.17, 3.53, 1.11, "white")
		heart(api, H, CFrame.new(sx * 0.9, 3.6, 1.1), 0.42, 0.1, c)
		api.add(H, 0.1, 0.1, 0.95, sx * 1.04, 3.5, 0.6, c)
	end
	heart(api, H, CFrame.new(0, 3.5, 1.09), 0.3, 0.1, c)
end

-- a round rim and lens round each eye (behind the eyes' front, so they show through), a bridge and arms
FACE.round_glasses = function(api, c, a, _ctx)
	local H = api.HEAD
	for _, sx in { -1, 1 } do
		disc(api, H, 0.74, 0.1, sx * 0.45, 3.4, 1.03, c)
		disc(api, H, 0.56, 0.1, sx * 0.45, 3.4, 1.05, a)
		api.add(H, 0.1, 0.1, 0.95, sx * 1.04, 3.5, 0.6, c)
	end
	api.add(H, 0.2, 0.1, 0.1, 0, 3.48, 1.06, c)
end

-- pushed up on the forehead: a strap round the head, two round rims with lenses in the accent, glints
FACE.goggles = function(api, c, a, ctx)
	local H = api.HEAD
	local y = 4.05
	local zf, zb, side = 1.2, -1.31, 1.2
	if ctx.bald then
		zf, zb, side = 1.06, -1.06, 1.06
	end
	api.add(H, side * 2, 0.22, 0.1, 0, y, zf - 0.05, c)
	api.add(H, side * 2, 0.22, 0.1, 0, y, zb, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.1, 0.22, zf - zb, sx * side, y, (zf + zb) / 2, c)
		disc(api, H, 0.62, 0.15, sx * 0.42, y, zf + 0.02, c)
		disc(api, H, 0.44, 0.12, sx * 0.42, y, zf + 0.08, a)
		api.add(H, 0.1, 0.1, 0.1, sx * 0.42 - 0.1, y + 0.1, zf + 0.15, "white")
	end
	api.add(H, 0.24, 0.12, 0.12, 0, y, zf + 0.02, c)
end

-- a shiny round nose with a glint, rosy cheeks
FACE.clown_nose = function(api, c, a, _ctx)
	local H = api.HEAD
	api.ball(H, 0.36, 0, 3.12, 1.12, c)
	api.ball(H, 0.12, 0.07, 3.2, 1.26, a)
	for _, sx in { -1, 1 } do
		disc(api, H, 0.3, 0.1, sx * 0.72, 2.98, 1.02, "pink")
	end
end

-- a pink nose and three whiskers a side, fanned, poking out past the cheeks
FACE.whiskers = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 0.22, 0.14, 0.1, 0, 3.05, 1.06, a)
	api.add(H, 0.12, 0.08, 0.1, 0, 2.97, 1.06, a)
	for _, sx in { -1, 1 } do
		for k = -1, 1 do
			api.add(H, 0.6, 0.1, 0.1, sx * 0.84, 3.0 + k * 0.13, 1.06, c, ANG(0, 0, sx * k * 0.18))
		end
	end
end

-- a plaster on one cheek (its pad in the accent) and a crossed pair on the other
FACE.bandage = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 0.5, 0.2, 0.1, 0.66, 3.0, 1.04, c, ANG(0, 0, 0.35))
	api.add(H, 0.16, 0.16, 0.1, 0.66, 3.0, 1.06, a, ANG(0, 0, 0.35))
	api.add(H, 0.42, 0.16, 0.1, -0.68, 2.98, 1.04, c, ANG(0, 0, 0.7))
	api.add(H, 0.42, 0.16, 0.1, -0.68, 2.98, 1.05, c, ANG(0, 0, -0.7))
	api.add(H, 0.12, 0.12, 0.1, -0.68, 2.98, 1.07, a)
end

-- a moustache over the mouth, its ends curling up and round
FACE.curly_moustache = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 0.36, 0.16, 0.12, 0, 3.0, 1.06, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.34, 0.15, 0.12, sx * 0.3, 2.97, 1.06, c, ANG(0, 0, -sx * 0.25))
		link(api, H, sx * 0.44, 2.93, 1.06, sx * 0.62, 2.95, 1.06, 0.12, c)
		link(api, H, sx * 0.62, 2.95, 1.06, sx * 0.68, 3.06, 1.06, 0.11, a)
		api.ball(H, 0.13, sx * 0.6, 3.08, 1.06, a)
	end
end

-- a full beard under the chin and up the cheeks (the mouth stays bare), sideburns, a darker moustache
FACE.beard = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 1.4, 0.5, 0.35, 0, 2.45, 0.9, c)
	api.add(H, 0.7, 0.3, 0.3, 0, 2.12, 0.85, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.45, 0.6, 0.25, sx * 0.79, 2.72, 0.96, c)
		api.add(H, 0.2, 0.75, 0.5, sx * 0.96, 3.1, 0.7, c)
		api.add(H, 0.3, 0.16, 0.12, sx * 0.36, 2.98, 1.06, a, ANG(0, 0, -sx * 0.2))
	end
	api.add(H, 0.4, 0.17, 0.12, 0, 3.02, 1.06, a)
end

-- a big heart painted on one cheek, a little one in the accent on the other
FACE.heart_paint = function(api, c, a, _ctx)
	local H = api.HEAD
	heart(api, H, CFrame.new(0.68, 2.98, 1.0), 0.42, 0.1, c)
	heart(api, H, CFrame.new(-0.7, 3.0, 1.0), 0.26, 0.1, a)
end

-- a star painted on one cheek, a four-pointed sparkle in the accent on the other
FACE.star_paint = function(api, c, a, _ctx)
	local H = api.HEAD
	star(api, H, CFrame.new(0.66, 2.98, 1.0), 0.13, 0.1, c)
	api.add(H, 0.1, 0.34, 0.1, -0.7, 3.0, 1.01, a)
	api.add(H, 0.34, 0.1, 0.1, -0.7, 3.0, 1.01, a)
end

-- an anime sweat drop by the temple and a smaller one below it
FACE.sweat_drop = function(api, c, a, _ctx)
	local H = api.HEAD
	api.ball(H, 0.32, 0.82, 3.74, 1.16, c)
	api.add(H, 0.22, 0.22, 0.14, 0.82, 3.9, 1.16, c, DIAMOND)
	api.add(H, 0.1, 0.1, 0.1, 0.77, 3.71, 1.3, a)
	api.ball(H, 0.18, 1.04, 3.42, 0.95, c)
	api.add(H, 0.13, 0.13, 0.1, 1.04, 3.51, 0.95, c, DIAMOND)
end

-- a glowing band over the eyes wrapping round to the ears, glints across it
FACE.visor = function(api, c, a, _ctx)
	local H = api.HEAD
	api.add(H, 2.1, 0.45, 0.15, 0, 3.42, 1.12, c)
	api.glow()
	api.add(H, 2.12, 0.1, 0.17, 0, 3.66, 1.12, "ink")
	for _, sx in { -1, 1 } do
		api.add(H, 0.12, 0.3, 1.05, sx * 1.07, 3.45, 0.55, "ink")
	end
	api.add(H, 0.32, 0.1, 0.1, 0.45, 3.5, 1.21, a, ANG(0, 0, 0.45))
	api.add(H, 0.16, 0.1, 0.1, 0.72, 3.38, 1.21, a, ANG(0, 0, 0.45))
end

-- dabs of icing on a cheek and the nose, a drip, sprinkles in the accent, a swipe on the other cheek
FACE.icing_smudge = function(api, c, a, _ctx)
	local H = api.HEAD
	disc(api, H, 0.36, 0.1, -0.62, 3.0, 1.02, c)
	disc(api, H, 0.22, 0.1, -0.44, 2.88, 1.02, c)
	api.add(H, 0.12, 0.22, 0.1, -0.66, 2.8, 1.02, c)
	api.add(H, 0.1, 0.1, 0.1, -0.66, 3.04, 1.07, a)
	api.add(H, 0.1, 0.1, 0.1, -0.54, 2.94, 1.07, a, DIAMOND)
	api.ball(H, 0.2, 0.04, 3.1, 1.06, c)
	api.add(H, 0.42, 0.12, 0.1, 0.66, 2.98, 1.02, c, ANG(0, 0, -0.15))
end

------------------------------------------------------------------ back

local BACK: { [string]: Draw } = {}

-- a rounded pack with a flap and buckle, a pocket in the accent, a handle and straps over the shoulders
BACK.backpack = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.15, 1.1, 0.5, 0, 1.65, -0.78, c)
	api.add(R, 1.15, 0.5, 0.5, 0, 2.2, -0.78, c, nil, "Cylinder")
	api.add(R, 1.17, 0.45, 0.1, 0, 2.1, -1.05, a)
	api.add(R, 0.2, 0.16, 0.08, 0, 1.88, -1.1, "yellow")
	api.add(R, 0.75, 0.45, 0.16, 0, 1.38, -1.1, a)
	api.add(R, 0.4, 0.12, 0.12, 0, 2.5, -0.78, a)
	straps(api, a)
end

-- a long cape from a mantle on the shoulders, flaring at the hem; the edges and hem in the accent, clasps in front
BACK.cape = function(api, c, a, _ctx)
	local R = api.ROOT
	local F = CFrame.new(0, 1.5, -0.62) * ANG(0.12, 0, 0)
	fput(api, R, F, 1.75, 2.0, 0.15, 0, 0, 0, c)
	fput(api, R, F, 2.0, 0.6, 0.15, 0, -0.95, -0.02, c)
	for _, sx in { -1, 1 } do
		fput(api, R, F, 0.14, 2.0, 0.18, sx * 0.88, 0, 0, a)
		api.ball(R, 0.2, sx * 0.32, 2.32, 0.6, a)
	end
	fput(api, R, F, 2.05, 0.15, 0.18, 0, -1.25, -0.02, a)
	api.add(R, 1.9, 0.3, 1.3, 0, 2.4, -0.05, c)
	api.add(R, 0.5, 0.1, 0.1, 0, 2.32, 0.65, a)
end

-- the Sugar Rush track's Rainbow Cape (the user: "the rainbow cape isnt actually a rainbow cape"): the cape's shape,
-- its fall in six rainbow bands top to bottom (red, orange, yellow, green and blue down the back, purple on the flared
-- hem), the edges, the hem line and the mantle in the accent (white), a yellow clasp in front
BACK.rainbow_cape = function(api, c, a, _ctx)
	local R = api.ROOT
	local F = CFrame.new(0, 1.5, -0.62) * ANG(0.12, 0, 0)
	-- the bands between the mantle and the hem's top (-0.65), so each one shows: red from under the mantle
	local BANDS: { { col: string, top: number, bottom: number } } = {
		{ col = "berry_red", top = 1.0, bottom = 0.47 },
		{ col = "orange", top = 0.47, bottom = 0.19 },
		{ col = "yellow", top = 0.19, bottom = -0.09 },
		{ col = "green", top = -0.09, bottom = -0.37 },
		{ col = "blue", top = -0.37, bottom = -0.66 },
	}
	for _, band in BANDS do
		fput(api, R, F, 1.75, band.top - band.bottom + 0.01, 0.15, 0, (band.top + band.bottom) / 2, 0, band.col)
	end
	fput(api, R, F, 2.0, 0.6, 0.15, 0, -0.95, -0.02, c)
	for _, sx in { -1, 1 } do
		fput(api, R, F, 0.14, 2.0, 0.18, sx * 0.88, 0, 0, a)
		api.ball(R, 0.2, sx * 0.32, 2.32, 0.6, a)
	end
	fput(api, R, F, 2.05, 0.15, 0.18, 0, -1.25, -0.02, a)
	api.add(R, 1.9, 0.3, 1.3, 0, 2.4, -0.05, a)
	api.add(R, 0.5, 0.1, 0.1, 0, 2.32, 0.65, "yellow")
end

-- the Royal Cape (it was the Red Cape's model in purple): the cape's shape in the colour with an ermine mantle and
-- broad ermine edges and hem (white, dotted with black tails), a small crown in the accent on the back and gold clasps
BACK.royal_cape = function(api, c, a, _ctx)
	local R = api.ROOT
	local F = CFrame.new(0, 1.5, -0.62) * ANG(0.12, 0, 0)
	fput(api, R, F, 1.75, 2.0, 0.15, 0, 0, 0, c)
	fput(api, R, F, 2.0, 0.6, 0.15, 0, -0.95, -0.02, c)
	for _, sx in { -1, 1 } do
		fput(api, R, F, 0.32, 2.0, 0.2, sx * 0.86, 0.02, -0.01, "white")
		for _, y in { 0.62, 0.02, -0.58 } do
			fput(api, R, F, 0.08, 0.16, 0.06, sx * 0.86, y, -0.12, "ink")
		end
		api.ball(R, 0.2, sx * 0.32, 2.32, 0.6, a)
	end
	fput(api, R, F, 2.1, 0.34, 0.2, 0, -1.18, -0.03, "white")
	for _, x in { -0.68, -0.23, 0.23, 0.68 } do
		fput(api, R, F, 0.08, 0.16, 0.06, x, -1.18, -0.15, "ink")
	end
	-- the ermine mantle over the shoulders, its tails on the back
	api.add(R, 1.95, 0.34, 1.35, 0, 2.4, -0.05, "white")
	for _, x in { -0.55, 0, 0.55 } do
		api.add(R, 0.08, 0.14, 0.06, x, 2.4, -0.75, "ink")
	end
	-- the crown on the back: a band and three points
	fput(api, R, F, 0.6, 0.18, 0.06, 0, 0.32, -0.1, a)
	for _, x in { -0.22, 0, 0.22 } do
		fput(api, R, F, 0.22, 0.22, 0.06, x, if x == 0 then 0.5 else 0.46, -0.1, a, DIAMOND)
	end
	api.add(R, 0.5, 0.1, 0.1, 0, 2.32, 0.65, a)
end

-- feathered wings swept up beside the head: a covert along the arm edged in the accent, five feathers fanning down
BACK.angel_wings = function(api, c, a, _ctx)
	local turn, cx, cy, len = 0.6, 1.0, 0.9, 1.9
	for _, sx in { -1, 1 } do
		local W = wingFrame(sx, 2.2, 0.42)
		wpanel(api, W, sx, cx, cy, len, 0.6, 0.16, turn, c)
		wpanel(api, W, sx, cx - 0.3 * sin(turn), cy + 0.3 * cos(turn), len + 0.05, 0.14, 0.2, turn, a)
		for k = 0, 4 do
			local f = 0.1 + k * 0.21
			local tx = cx + len * cos(turn) * (f - 0.5) + 0.3 * sin(turn)
			local ty = cy + len * sin(turn) * (f - 0.5) - 0.3 * cos(turn)
			local L = 0.6 + k * 0.22
			wpanel(api, W, sx, tx, ty - L / 2 + 0.12, 0.3, L, 0.12, 0.12 * k - 0.1, c)
		end
	end
end

-- teardrop fairy wings: a long upper wing and a short lower one, round ends tapering to the root, veins, a sparkle
BACK.fairy_wings = function(api, c, a, _ctx)
	local R = api.ROOT
	for _, sx in { -1, 1 } do
		local W = wingFrame(sx, 2.05, 0.3)
		local U = W * CFrame.new(sx * 0.4, 0.4, 0) * ANG(0, 0, -sx * 0.62)
		fput(api, R, U, 0.7, 0.7, 0.1, 0, 0.55, 0, c, DIAMOND)
		fdisc(api, R, U, 0.98, 0.1, 0, 1.05, 0, c)
		fput(api, R, U, 0.12, 1.2, 0.14, 0, 0.7, 0, a)
		local L = W * CFrame.new(sx * 0.32, -0.15, 0) * ANG(0, 0, -sx * 2.25)
		fput(api, R, L, 0.48, 0.48, 0.1, 0, 0.32, 0, c, DIAMOND)
		fdisc(api, R, L, 0.68, 0.1, 0, 0.62, 0, c)
		fput(api, R, L, 0.12, 0.75, 0.14, 0, 0.4, 0, a)
		fball(api, R, U, 0.18, 0, 1.3, 0.1, a)
		api.glow()
	end
end

-- round butterfly wings: a big upper and a smaller lower disc with black borders and veins, a white dot
BACK.butterfly_wings = function(api, c, a, _ctx)
	for _, sx in { -1, 1 } do
		local W = wingFrame(sx, 2.1, 0.4)
		wdisc(api, W, sx, 0.9, 0.62, 1.55, 0.1, a)
		wdisc(api, W, sx, 0.92, 0.62, 1.22, 0.14, c)
		wdisc(api, W, sx, 0.68, -0.42, 1.1, 0.1, a)
		wdisc(api, W, sx, 0.69, -0.42, 0.82, 0.14, c)
		wpanel(api, W, sx, 0.88, 0.6, 1.1, 0.1, 0.18, 0.7, a)
		wpanel(api, W, sx, 0.66, -0.4, 0.8, 0.1, 0.18, -0.6, a)
		wpanel(api, W, sx, 1.42, 1.08, 0.14, 0.14, 0.16, 0, "white")
	end
end

-- bat-like dragon wings: an arm bone in the accent up and out to a claw, finger bones, pointed membranes
BACK.dragon_wings = function(api, c, a, _ctx)
	local R = api.ROOT
	for _, sx in { -1, 1 } do
		local W = wingFrame(sx, 2.05, 0.42)
		wpanel(api, W, sx, 0.88, 0.42, 0.85, 1.2, 0.12, -0.3, c)
		wpanel(api, W, sx, 1.5, 0.55, 0.62, 1.15, 0.12, -0.55, c)
		wpanel(api, W, sx, 1.68, 1.1, 0.6, 0.8, 0.12, -0.95, c)
		frod(api, R, W, sx * 0.1, 0.1, 0, 1.5, sx * 0.69, 0.18, 0.2, a)
		frod(api, R, W, sx * 1.05, 1.25, 0, 1.05, sx * 1.28, 0.16, 0.2, a)
		fput(api, R, W, 0.24, 0.24, 0.2, sx * 2.12, 1.6, 0, a, DIAMOND)
		frod(api, R, W, sx * 1.05, 1.25, 0, 1.45, sx * 2.75, 0.12, 0.18, a)
		frod(api, R, W, sx * 1.05, 1.25, 0, 1.25, sx * 2.25, 0.12, 0.18, a)
	end
end

-- two tanks with rounded tops on a plate, nozzles under them blowing glowing flames
BACK.jetpack = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.0, 1.0, 0.15, 0, 1.75, -0.58, "steel_dark")
	for _, sx in { -1, 1 } do
		local x = sx * 0.3
		api.cyl(R, 0.48, 1.1, x, 1.7, -0.84, c)
		api.ball(R, 0.48, x, 2.25, -0.84, c)
		api.cyl(R, 0.5, 0.12, x, 1.95, -0.84, "berry_red")
		api.cyl(R, 0.32, 0.2, x, 1.05, -0.84, "steel_dark")
		api.cyl(R, 0.26, 0.3, x, 0.8, -0.84, a)
		api.glow()
		api.ball(R, 0.2, x, 0.6, -0.84, "yellow")
		api.glow()
	end
end

-- a big ribbon bow on the back: two loops (their insides in the accent), a knot, two tails, a sash round the waist
BACK.big_bow = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.55, 0.3, 1.05, 0, 1.75, 0, c)
	for _, sx in { -1, 1 } do
		api.add(R, 1.0, 0.75, 0.3, sx * 0.55, 1.85, -0.78, c, ANG(0, 0, sx * 0.25))
		api.add(R, 0.5, 0.36, 0.1, sx * 0.6, 1.86, -0.95, a, ANG(0, 0, sx * 0.25))
		api.add(R, 0.3, 0.85, 0.15, sx * 0.24, 1.18, -0.72, c, ANG(0, 0, sx * 0.25))
	end
	api.add(R, 0.36, 0.42, 0.36, 0, 1.78, -0.82, a)
end

-- a stepped shell on a rim in the accent, scutes in the accent on top
BACK.turtle_shell = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.7, 1.75, 0.18, 0, 1.65, -0.6, a)
	api.add(R, 1.5, 1.55, 0.2, 0, 1.65, -0.79, c)
	api.add(R, 1.15, 1.2, 0.2, 0, 1.65, -0.99, c)
	api.add(R, 0.7, 0.75, 0.15, 0, 1.65, -1.15, c)
	api.add(R, 0.4, 0.4, 0.1, 0, 1.65, -1.24, a, DIAMOND)
	for _, p in { { -0.38, 2.0 }, { 0.38, 2.0 }, { -0.38, 1.3 }, { 0.38, 1.3 } } do
		api.add(R, 0.26, 0.26, 0.1, p[1], p[2], -1.1, a, DIAMOND)
	end
end

-- a teddy bear hugging the back, looking out behind: body, head, ears, a snout in the accent, eyes, paws
BACK.teddy_backpack = function(api, c, a, _ctx)
	local R = api.ROOT
	api.ball(R, 0.95, 0, 1.55, -0.95, c)
	api.ball(R, 0.55, 0, 1.5, -1.24, a)
	api.ball(R, 0.75, 0, 2.15, -1.12, c)
	api.ball(R, 0.3, 0, 2.06, -1.46, a)
	api.ball(R, 0.12, 0, 2.12, -1.6, "ink")
	for _, sx in { -1, 1 } do
		api.ball(R, 0.3, sx * 0.3, 2.45, -1.1, c)
		api.add(R, 0.1, 0.14, 0.1, sx * 0.15, 2.26, -1.46, "ink")
		api.ball(R, 0.3, sx * 0.5, 1.75, -0.86, c)
		api.ball(R, 0.32, sx * 0.3, 1.1, -1.0, c)
	end
end

-- a guitar slung on the back, neck up over a shoulder and leaning back from the head, its strap across the chest
BACK.guitar = function(api, c, a, _ctx)
	local R = api.ROOT
	local F = CFrame.new(0, 1.6, -0.82) * ANG(-0.3, 0, 0.6)
	fdisc(api, R, F, 0.95, 0.3, 0, -0.35, 0, c)
	fdisc(api, R, F, 0.72, 0.3, 0, 0.18, 0, c)
	fdisc(api, R, F, 0.28, 0.1, 0, -0.02, -0.12, a)
	fput(api, R, F, 0.36, 0.1, 0.1, 0, -0.5, -0.15, a)
	fput(api, R, F, 0.18, 1.2, 0.12, 0, 1.05, 0, a)
	fput(api, R, F, 0.26, 0.32, 0.12, 0, 1.78, 0, c)
	link(api, R, -0.6, 1.15, 0.73, 0.62, 2.38, 0.73, 0.14, a)
end

-- a two-tier cake on the back: sponge tiers in the accent, frosting and drips, a cherry on top, straps
BACK.cake_backpack = function(api, c, a, _ctx)
	local R = api.ROOT
	api.cyl(R, 1.1, 0.5, 0, 1.4, -1.08, a)
	api.cyl(R, 1.15, 0.15, 0, 1.72, -1.08, c)
	api.cyl(R, 0.8, 0.4, 0, 1.99, -1.08, a)
	api.cyl(R, 0.85, 0.12, 0, 2.24, -1.08, c)
	api.ball(R, 0.28, 0, 2.42, -1.08, "berry_red")
	for _, p in { { -0.3, 1.58, -1.55 }, { 0.12, 1.55, -1.63 }, { 0.42, 1.6, -1.45 } } do
		api.add(R, 0.14, 0.28, 0.12, p[1], p[2], p[3], c)
	end
	straps(api, c)
end

-- little round see-through-blue wings in pairs, white veins, a striped yellow mount between them
BACK.bee_wings = function(api, c, a, _ctx)
	local R = api.ROOT
	api.ball(R, 0.42, 0, 2.0, -0.62, a)
	api.add(R, 0.44, 0.12, 0.32, 0, 2.0, -0.66, "black")
	for _, sx in { -1, 1 } do
		local W = wingFrame(sx, 2.05, 0.35)
		local U = W * CFrame.new(sx * 0.3, 0.25, 0) * ANG(0, 0, -sx * 0.8)
		fdisc(api, R, U, 0.95, 0.1, 0, 0.45, 0, c)
		fput(api, R, U, 0.1, 0.75, 0.14, 0, 0.4, 0, "white")
		local L = W * CFrame.new(sx * 0.25, -0.05, 0) * ANG(0, 0, -sx * 1.95)
		fdisc(api, R, L, 0.65, 0.1, 0, 0.32, 0, c)
		fput(api, R, L, 0.1, 0.5, 0.14, 0, 0.28, 0, "white")
	end
end

-- a paper bag on the back with two baguettes in the accent poking out of the top in a V, plump enough to read from
-- behind (they were thin sticks there), scored on the side that faces back, and straps
BACK.baguette_bag = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.0, 0.95, 0.45, 0, 1.55, -0.78, c)
	api.add(R, 1.02, 0.15, 0.47, 0, 1.98, -0.78, "cream")
	for _, b in { { -0.2, 0.34, -0.38 }, { 0.22, -0.28, -0.42 } } do
		local F = CFrame.new(b[1], 1.95, -0.82) * ANG(b[3], 0, b[2])
		fcyl(api, R, F, 0.38, 1.3, 0.2, a)
		fball(api, R, F, 0.38, 0, 0.85, 0, a)
		for _, s in { 0.42, 0.7 } do
			fput(api, R, F, 0.26, 0.1, 0.1, 0, s, -0.17, c, ANG(0, 0, 0.5))
		end
	end
	straps(api, c)
end

-- a plump five-pointed star on the back with a sleepy smiling face (cheeks in the accent) looking out behind
BACK.star_backpack = function(api, c, a, _ctx)
	local R = api.ROOT
	local F = CFrame.new(0, 1.65, -0.85) * ANG(0, PI, 0)
	star(api, R, F, 0.42, 0.35, c)
	api.add(R, 0.1, 0.18, 0.1, -0.15, 1.72, -1.07, "ink")
	api.add(R, 0.1, 0.18, 0.1, 0.15, 1.72, -1.07, "ink")
	api.add(R, 0.2, 0.1, 0.1, 0, 1.55, -1.07, "ink")
	api.add(R, 0.15, 0.12, 0.1, -0.28, 1.6, -1.06, a)
	api.add(R, 0.15, 0.12, 0.1, 0.28, 1.6, -1.06, a)
end

------------------------------------------------------------------ neck

local NECK: { [string]: Draw } = {}

-- a band round the neck, a big triangle down the chest knotted at one side, white dots
NECK.neckerchief = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.7, 0.3, 1.2, 0, 2.4, 0, c)
	api.add(R, 0.7, 0.7, 0.15, 0, 2.1, 0.74, c, DIAMOND)
	api.add(R, 0.24, 0.24, 0.2, 0.38, 2.22, 0.75, a)
	api.add(R, 0.14, 0.32, 0.12, 0.45, 1.99, 0.77, a, ANG(0, 0, 0.3))
	api.add(R, 0.14, 0.28, 0.12, 0.3, 2.0, 0.77, a, ANG(0, 0, -0.3))
	api.add(R, 0.1, 0.1, 0.1, -0.1, 1.95, 0.82, "white")
	api.add(R, 0.1, 0.1, 0.1, 0.1, 1.78, 0.82, "white")
end

-- a scarf wound round the neck with an accent stripe, one end hanging down the chest with stripes and a fringe
NECK.scarf = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.8, 0.45, 1.45, 0, 2.38, 0, c)
	api.add(R, 1.82, 0.12, 1.47, 0, 2.38, 0, a)
	local F = CFrame.new(0.35, 1.85, 0.82) * ANG(0.1, 0, 0.08)
	fput(api, R, F, 0.45, 0.9, 0.18, 0, 0, 0, c)
	fput(api, R, F, 0.47, 0.12, 0.2, 0, 0.15, 0, a)
	fput(api, R, F, 0.47, 0.12, 0.2, 0, -0.15, 0, a)
	fput(api, R, F, 0.4, 0.14, 0.14, 0, -0.52, 0, a)
	api.add(R, 0.4, 0.6, 0.15, 0.12, 1.95, 0.76, c, ANG(0, 0, -0.12))
end

-- the Crunchy track's Crumble Scarf (it was the striped scarf in brown): a chunky scarf (the colour) whose edges
-- crumble into lumps of crumble topping (golden, the accent and dark ones) round the neck, one end hanging down the
-- chest with lumps on it and a ragged, broken-off end, and two crumbs falling under it
NECK.crumble_scarf = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.8, 0.45, 1.45, 0, 2.38, 0, c)
	-- { x, y, z, size } and its colour: golden, dark and the accent
	local LUMPS: { { number } } = {
		{ -0.62, 2.6, 0.62, 0.26 },
		{ -0.28, 2.58, 0.74, 0.22 },
		{ 0.05, 2.62, 0.72, 0.26 },
		{ 0.62, 2.6, 0.6, 0.24 },
		{ 0.88, 2.58, 0.25, 0.24 },
		{ -0.88, 2.58, 0.2, 0.22 },
		{ -0.45, 2.22, 0.74, 0.2 },
		{ 0.72, 2.2, 0.7, 0.2 },
		{ 0.9, 2.45, -0.3, 0.22 },
	}
	local LUMP_COLS = { "sponge", "wood_dark", a, "sponge", "wood_dark", a, a, "sponge", "sponge" }
	for i, l in LUMPS do
		api.ball(R, l[4], l[1], l[2], l[3], LUMP_COLS[i])
	end
	local F = CFrame.new(0.32, 1.88, 0.82) * ANG(0.1, 0, 0.08)
	fput(api, R, F, 0.48, 0.78, 0.2, 0, 0.04, 0, c)
	-- the ragged end: three teeth of different lengths
	fput(api, R, F, 0.16, 0.22, 0.2, -0.16, -0.44, 0, c)
	fput(api, R, F, 0.16, 0.14, 0.2, 0, -0.4, 0, c)
	fput(api, R, F, 0.16, 0.28, 0.2, 0.16, -0.47, 0, c)
	fball(api, R, F, 0.24, -0.1, 0.2, 0.1, "sponge")
	fball(api, R, F, 0.2, 0.13, 0.0, 0.1, "wood_dark")
	fball(api, R, F, 0.22, -0.08, -0.22, 0.1, a)
	fball(api, R, F, 0.18, 0.14, 0.32, 0.09, "sponge")
	fput(api, R, F, 0.1, 0.1, 0.1, -0.02, -0.72, 0.04, "sponge", DIAMOND)
	fput(api, R, F, 0.08, 0.08, 0.08, 0.2, -0.86, 0.04, a, DIAMOND)
	api.add(R, 0.42, 0.6, 0.17, 0.1, 1.95, 0.76, c, ANG(0, 0, -0.12))
end

-- a bow tie under the chin over two white collar points: wings narrow at the knot, wider at the ends
NECK.bow_tie = function(api, c, a, _ctx)
	local R = api.ROOT
	for _, sx in { -1, 1 } do
		api.add(R, 0.28, 0.28, 0.1, sx * 0.17, 2.24, 0.72, "white", DIAMOND)
		api.add(R, 0.34, 0.32, 0.14, sx * 0.22, 2.08, 0.79, c)
		api.add(R, 0.16, 0.46, 0.14, sx * 0.42, 2.08, 0.79, c)
	end
	api.add(R, 0.22, 0.22, 0.18, 0, 2.08, 0.83, a)
end

-- a knot under the chin, a long blade with a pointed tip, diagonal stripes in the accent, white collar points
NECK.necktie = function(api, c, a, _ctx)
	local R = api.ROOT
	for _, sx in { -1, 1 } do
		api.add(R, 0.26, 0.26, 0.1, sx * 0.17, 2.3, 0.7, "white", DIAMOND)
	end
	api.add(R, 0.24, 0.2, 0.15, 0, 2.24, 0.76, c)
	api.add(R, 0.3, 0.72, 0.12, 0, 1.78, 0.76, c)
	api.add(R, 0.21, 0.21, 0.12, 0, 1.42, 0.76, c, DIAMOND)
	api.add(R, 0.3, 0.1, 0.14, 0, 1.92, 0.77, a, ANG(0, 0, 0.5))
	api.add(R, 0.3, 0.1, 0.14, 0, 1.66, 0.77, a, ANG(0, 0, 0.5))
end

-- The three necklaces that were one string of beads in different colours (Pearl Necklace, Gold Chain, Bonbon
-- Necklace) each have a look of their own. They hang on the same curve: from beside the neck down to the middle of
-- the chest, `drop` studs below the shoulders' height (2.42) and `out` studs out front at the bottom.
local function neckCurve(u: number, drop: number, out: number): Vector3
	return Vector3.new(0.62 * u, 2.42 - drop * (1 - u * u), 0.5 + out * (1 - u * u))
end

-- Pearl Necklace: two strands of small, even pearls (the colour, every third in the accent's sheen), the second
-- hanging lower, a bigger pearl in the middle of each
NECK.pearls = function(api, c, a, _ctx)
	local R = api.ROOT
	for s, strand in { { n = 11, drop = 0.4, out = 0.3 }, { n = 13, drop = 0.64, out = 0.34 } } do
		for i = 0, strand.n - 1 do
			local u = -1 + 2 * i / (strand.n - 1)
			local p = neckCurve(u * (if s == 2 then 1.06 else 1), strand.drop, strand.out)
			local mid = i == (strand.n - 1) / 2
			api.ball(R, if mid then 0.24 else 0.17, p.X, p.Y, p.Z, if i % 3 == 1 then a else c)
		end
	end
end

-- Gold Chain: a heavy chain of links hanging low on the chest, flat links (the colour) and links seen edge on (the
-- accent) by turns, so it reads as links rather than beads
NECK.gold_chain = function(api, c, a, _ctx)
	local R = api.ROOT
	local n = 14
	local prev = neckCurve(-1.04, 0.62, 0.34)
	for i = 1, n do
		local p = neckCurve(-1.04 + 2.08 * i / n, 0.62, 0.34)
		local mid = (prev + p) / 2
		local len = (p - prev).Magnitude
		local F = CFrame.lookAt(mid, p, Vector3.new(0, 0, 1))
		if i % 2 == 1 then
			api.add(R, 0.2, 0.08, len + 0.04, mid.X, mid.Y, mid.Z, c, F.Rotation)
			api.add(R, 0.08, 0.1, len * 0.4, mid.X, mid.Y, mid.Z, "choco_dark", F.Rotation)
		else
			api.add(R, 0.07, 0.18, len + 0.04, mid.X, mid.Y, mid.Z, a, F.Rotation)
		end
		prev = p
	end
end

-- Bonbon Necklace: three wrapped bonbons strung on a white thread, a big one in the middle (the colour) and one each
-- side (the accent), each wrapper twisted into a fan at both ends in the other colour
NECK.bonbon_necklace = function(api, c, a, _ctx)
	local R = api.ROOT
	local n = 10
	local prev = neckCurve(-1, 0.5, 0.32)
	for i = 1, n do
		local p = neckCurve(-1 + 2 * i / n, 0.5, 0.32)
		link(api, R, prev.X, prev.Y, prev.Z, p.X, p.Y, p.Z, 0.05, "white")
		prev = p
	end
	local BONBONS: { { u: number, d: number, col: string, wrap: string } } = {
		{ u = 0, d = 0.36, col = c, wrap = a },
		{ u = -0.66, d = 0.28, col = a, wrap = c },
		{ u = 0.66, d = 0.28, col = a, wrap = c },
	}
	for _, b in BONBONS do
		local u, d, col, wrap = b.u, b.d, b.col, b.wrap
		local p = neckCurve(u, 0.5, 0.36)
		-- along the thread: the curve's slope there
		local F = CFrame.new(p) * ANG(0, 0, math.atan2(2 * 0.5 * u, 0.62))
		fball(api, R, F, d, 0, 0, 0, col)
		for _, sx in { -1, 1 } do
			fput(api, R, F, 0.1, d * 0.5, 0.1, sx * (d * 0.5 + 0.02), 0, 0, wrap)
			fput(api, R, F, 0.1, d * 0.78, 0.1, sx * (d * 0.5 + 0.11), 0, 0, wrap)
		end
		fput(api, R, F, 0.08, 0.08, 0.06, -d * 0.18, d * 0.2, d * 0.45, "white")
	end
end

-- a collar with a big gold bell hanging from its front
NECK.bell_collar = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.62, 0.25, 1.2, 0, 2.38, 0, c)
	api.add(R, 1.0, 0.22, 0.15, 0, 2.24, 0.68, c)
	api.ball(R, 0.44, 0, 1.96, 0.82, a)
	api.add(R, 0.24, 0.1, 0.1, 0, 1.9, 1.02, "ink")
	api.ball(R, 0.13, 0, 1.76, 0.86, a)
	api.add(R, 0.12, 0.14, 0.12, 0, 2.2, 0.82, a)
end

-- a wide pleated ruff round the neck: two layers and scallops round the rim in the accent
NECK.ruff = function(api, c, a, _ctx)
	local R = api.ROOT
	api.cyl(R, 2.3, 0.22, 0, 2.42, 0, c)
	api.cyl(R, 2.05, 0.2, 0, 2.24, 0, c)
	for k = 0, 7 do
		local ang = (k + 0.5) * PI / 4
		api.ball(R, 0.28, cos(ang) * 1.08, 2.32, sin(ang) * 1.08, a)
	end
end

-- a garland of flowers in the two colours by turns, down over the chest and round the back
NECK.lei = function(api, c, a, _ctx)
	local R = api.ROOT
	for k = 0, 9 do
		local ang = k * 2 * PI / 10 + PI / 2
		local s = sin(ang)
		api.ball(R, 0.32, cos(ang) * 0.64, 2.28 - 0.42 * s, 0.05 + 0.74 * s, if k % 2 == 0 then c else a)
	end
	for _, sx in { -1, 1 } do
		api.add(R, 0.2, 0.2, 0.1, sx * 0.3, 1.85, 0.92, "green", DIAMOND)
	end
end

-- a ribbon in the accent round the neck down to a gold medal with a star
NECK.medal = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.6, 0.14, 1.1, 0, 2.42, 0, a)
	for _, sx in { -1, 1 } do
		link(api, R, sx * 0.36, 2.36, 0.72, sx * 0.06, 1.86, 0.78, 0.18, a)
	end
	disc(api, R, 0.46, 0.12, 0, 1.7, 0.82, c)
	disc(api, R, 0.3, 0.1, 0, 1.7, 0.86, "plate_gold")
	api.add(R, 0.14, 0.14, 0.1, 0, 1.7, 0.92, "white", DIAMOND)
end

-- a fine chain down to a heart locket, a small heart in the accent set in it
NECK.locket = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.6, 0.1, 1.1, 0, 2.42, 0, c)
	for _, sx in { -1, 1 } do
		link(api, R, sx * 0.4, 2.36, 0.68, sx * 0.04, 1.98, 0.78, 0.1, c)
	end
	heart(api, R, CFrame.new(0, 1.86, 0.8), 0.42, 0.1, c)
	heart(api, R, CFrame.new(0, 1.87, 0.84), 0.22, 0.1, a)
	api.glow()
end

-- a band round the neck with a glowing gem in the accent hanging from its front, little studs
NECK.choker = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.6, 0.2, 1.15, 0, 2.38, 0, c)
	api.add(R, 0.9, 0.2, 0.12, 0, 2.24, 0.66, c)
	disc(api, R, 0.34, 0.1, 0, 2.0, 0.75, c)
	api.add(R, 0.24, 0.24, 0.12, 0, 2.0, 0.8, a, DIAMOND)
	api.glow()
	for _, sx in { -1, 1 } do
		api.ball(R, 0.12, sx * 0.3, 2.2, 0.72, a)
	end
end

-- a chain in the accent down to a star pendant
NECK.pendant = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.6, 0.1, 1.1, 0, 2.42, 0, a)
	for _, sx in { -1, 1 } do
		link(api, R, sx * 0.4, 2.36, 0.68, sx * 0.04, 2.0, 0.78, 0.1, a)
	end
	star(api, R, CFrame.new(0, 1.84, 0.82), 0.12, 0.1, c)
end

-- the boa's path: round the neck, one end down the chest, the other thrown back over the shoulder
local BOA_PUFFS: { { number } } = {
	{ -0.62, 2.42, 0.2 },
	{ -0.5, 2.4, -0.4 },
	{ 0.05, 2.45, -0.62 },
	{ 0.55, 2.42, 0.25 },
	{ -0.48, 2.18, 0.7 },
	{ -0.44, 1.88, 0.76 },
	{ -0.47, 1.58, 0.76 },
	{ -0.5, 1.3, 0.74 },
	{ 0.42, 2.16, 0.7 },
	{ 0.58, 2.3, -0.4 },
	{ 0.54, 2.0, -0.64 },
	{ 0.5, 1.72, -0.66 },
}

-- a fluffy feather boa along that path: round puffs (every third in the accent), a smaller tuft bulging out of each
-- to one side and the other by turns, so its edge is ruffled
NECK.boa = function(api, c, a, _ctx)
	local R = api.ROOT
	for i, p in BOA_PUFFS do
		api.ball(R, 0.38, p[1], p[2], p[3], if i % 3 == 0 then a else c)
		local sx = if i % 2 == 0 then 1 else -1
		api.ball(R, 0.24, p[1] + sx * 0.19, p[2] + 0.1, p[3] + 0.05, if i % 3 == 1 then a else c)
	end
end

-- the Soft track's Marshmallow Boa (it was the feather boa in white): marshmallows strung along the boa's path,
-- squat cylinders in the accent, the colour and sky blue by turns (the pastel marshmallows of the Marshmallow Wand)
NECK.marshmallow_boa = function(api, c, a, _ctx)
	local R = api.ROOT
	local cols = { a, c, "sky_day" }
	for i, p in BOA_PUFFS do
		api.cyl(R, 0.44, 0.36, p[1], p[2], p[3], cols[(i - 1) % 3 + 1])
	end
end

-- a round-flapped collar lying on the chest, scalloped lace along its edges in the accent, a button
NECK.lace_collar = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.6, 0.15, 1.1, 0, 2.42, 0, c)
	for _, sx in { -1, 1 } do
		disc(api, R, 0.6, 0.1, sx * 0.3, 2.1, 0.73, c)
		for k = 0, 2 do
			local ang = -PI / 2 + sx * (k - 1) * 0.75 - sx * 0.25
			api.ball(R, 0.14, sx * 0.3 + cos(ang) * 0.31, 2.1 + sin(ang) * 0.31, 0.76, a)
		end
	end
	api.ball(R, 0.14, 0, 2.2, 0.8, a)
end

------------------------------------------------------------------ hand

local HAND: { [string]: Draw } = {}

-- a wooden handle (the accent), a steel neck and a big slotted blade turned to the camera
HAND.spatula = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.18, 0.85, -0.05, a)
	fcyl(api, A, GRIP, 0.21, 0.12, 0.42, c)
	fput(api, A, GRIP_FACE, 0.14, 0.5, 0.1, 0, 0.72, 0, c)
	fput(api, A, GRIP_FACE, 0.62, 0.65, 0.1, 0, 1.25, 0, c)
	fput(api, A, GRIP_FACE, 0.1, 0.36, 0.12, -0.13, 1.28, 0, "steel_dark")
	fput(api, A, GRIP_FACE, 0.1, 0.36, 0.12, 0.13, 1.28, 0, "steel_dark")
end

-- a handle in the accent, a collar, and a cage of looped wires (two crossing loops) ending in a little cap
HAND.whisk = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.2, 0.75, 0, a)
	fcyl(api, A, GRIP, 0.24, 0.12, 0.42, c)
	for _, F in { GRIP_FACE, GRIP_FACE * ANG(0, PI / 2, 0) } do
		for _, sx in { -1, 1 } do
			frod(api, A, F, 0, 0.45, 0, 0.6, sx * 0.6, 0.11, 0.11, c)
			frod(api, A, F, sx * 0.34, 0.94, 0, 0.62, -sx * 0.56, 0.11, 0.11, c)
		end
	end
	fball(api, A, GRIP, 0.18, 0, 1.46, 0, c)
end

-- a rolling pin held by one handle: the barrel ringed in the accent near the ends, round knobs
HAND.rolling_pin = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.16, 0.42, 0, a)
	fcyl(api, A, GRIP, 0.4, 1.1, 0.75, c)
	fcyl(api, A, GRIP, 0.42, 0.1, 0.32, a)
	fcyl(api, A, GRIP, 0.42, 0.1, 1.18, a)
	fcyl(api, A, GRIP, 0.16, 0.3, 1.45, a)
	fball(api, A, GRIP, 0.2, 0, -0.22, 0, a)
	fball(api, A, GRIP, 0.2, 0, 1.62, 0, a)
end

-- a long handle and a round bowl, its hollow in the accent facing the camera
HAND.wooden_spoon = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.14, 1.05, 0.25, c)
	fcyl(api, A, GRIP, 0.16, 0.1, -0.2, a)
	fball(api, A, GRIP, 0.42, 0, 0.95, 0, c)
	fball(api, A, GRIP, 0.32, 0, 1.12, 0, c)
	fdisc(api, A, GRIP_FACE, 0.26, 0.1, 0, 1.0, 0.13, a)
end

-- the Chewy track's Taffy Spoon (it was the wooden spoon in pink): a wooden spoon with a glob of pulled taffy (the
-- colour, twists of the accent) heaped in its bowl, and a strand of it stretched off the bowl drooping in a loop back
-- to the handle
HAND.taffy_spoon = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.14, 1.05, 0.25, "wood")
	fcyl(api, A, GRIP, 0.16, 0.1, -0.2, "wood_dark")
	fball(api, A, GRIP, 0.42, 0, 0.95, 0, "wood")
	fball(api, A, GRIP, 0.46, 0, 1.05, 0.1, c)
	fball(api, A, GRIP, 0.32, 0.04, 1.3, 0.08, c)
	local B = faceBoth(GRIP_FACE * CFrame.new(0, 1.12, 0.1))
	fput(api, A, B, 0.3, 0.08, 0.08, 0, 0, 0.22, a, ANG(0, 0, 0.5))
	fput(api, A, B, 0.22, 0.08, 0.08, 0.04, 0.2, 0.15, a, ANG(0, 0, -0.5))
	-- the strand: off the bowl's side, out and down in a sag, back in to the handle (`up` along the handle, `side`
	-- across it as faceBoth turns it, so the loop shows in both views)
	local side = faceBoth(GRIP_FACE).RightVector
	local LOOP = { { 0.28, 0.94 }, { 0.46, 0.8 }, { 0.6, 0.6 }, { 0.62, 0.38 }, { 0.52, 0.18 }, { 0.34, 0.06 }, { 0.16, 0.08 } }
	for i, q in LOOP do
		local p = (GRIP_FACE * CFrame.new(0, q[2], 0)).Position + side * q[1]
		api.ball(A, if i == 1 then 0.24 else 0.19, p.X, p.Y, p.Z, if i % 3 == 0 then a else c)
	end
end

-- a bag (tip down) squeezed in the fist, icing in the accent at its open top and a blob at the nozzle
HAND.piping_bag = function(api, c, a, _ctx)
	local A = api.ARM_R
	local F = CFrame.new(1.05, 1.25, 0.55) * ANG(-0.25, 0, -0.15)
	fcyl(api, A, F, 0.5, 0.3, 0.38, c)
	fcyl(api, A, F, 0.42, 0.12, 0.56, a)
	fcyl(api, A, F, 0.2, 0.15, 0.62, c)
	fcyl(api, A, F, 0.4, 0.25, 0.1, c)
	fcyl(api, A, F, 0.28, 0.25, -0.15, c)
	fcyl(api, A, F, 0.16, 0.2, -0.37, c)
	fcyl(api, A, F, 0.12, 0.15, -0.52, "steel")
	fball(api, A, F, 0.18, 0, -0.66, 0, a)
end

-- a cupcake on the palm: a fluted case in the accent, a swirl of frosting, a cherry and two sprinkles
HAND.cupcake = function(api, c, a, _ctx)
	local A = api.ARM_R
	local x, y, z = 1.0, 1.45, 0.48
	api.cyl(A, 0.42, 0.12, x, y - 0.12, z, a)
	api.cyl(A, 0.52, 0.22, x, y + 0.04, z, a)
	api.cyl(A, 0.58, 0.15, x, y + 0.22, z, c)
	api.ball(A, 0.46, x, y + 0.33, z, c)
	api.ball(A, 0.3, x, y + 0.52, z, c)
	api.ball(A, 0.16, x, y + 0.68, z, "berry_red")
	api.add(A, 0.1, 0.1, 0.1, x + 0.12, y + 0.36, z + 0.2, "yellow", ANG(0, 0, 0.6))
	api.add(A, 0.1, 0.1, 0.1, x - 0.14, y + 0.3, z + 0.17, "blue", ANG(0, 0, -0.6))
end

-- a waffle cone in the accent (tip down in the fist), a scoop with a drip, a cherry
HAND.ice_cream_cone = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.4, 0.1, 0.42, a)
	fcyl(api, A, GRIP, 0.38, 0.2, 0.3, a)
	fcyl(api, A, GRIP, 0.3, 0.2, 0.12, a)
	fcyl(api, A, GRIP, 0.22, 0.2, -0.08, a)
	fcyl(api, A, GRIP, 0.12, 0.18, -0.27, a)
	fball(api, A, GRIP, 0.52, 0, 0.62, 0, c)
	fball(api, A, GRIP, 0.18, 0.08, 0.42, 0.2, c)
	fball(api, A, GRIP, 0.16, 0, 0.92, 0, "berry_red")
end

-- a stick in the accent and a round lollipop in rings of the two colours, facing between the camera and the Baker
-- screen's view (faceBoth)
HAND.lollipop = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.1, 0.95, 0.22, a)
	local P = faceBoth(GRIP_FACE * CFrame.new(0, 0.98, 0))
	fdisc(api, A, P, 0.72, 0.15, 0, 0, 0, c)
	fdisc(api, A, P, 0.52, 0.15, 0, 0, 0.02, a)
	fdisc(api, A, P, 0.34, 0.15, 0, 0, 0.04, c)
	fdisc(api, A, P, 0.14, 0.15, 0, 0, 0.06, a)
end

-- the Sugar Rush track's Swirl Lollipop (it was the ringed lollipop in purple): a bigger pop on a white stick, a
-- pinwheel swirl of six arms in the rainbow's colours curling out from its middle (the colour, with a dot of the
-- accent), facing between the camera and the customization screen's view (faceBoth)
HAND.swirl_lollipop = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.1, 1.1, 0.3, "white")
	local P = faceBoth(GRIP_FACE * CFrame.new(0, 1.22, 0))
	fdisc(api, A, P, 1.08, 0.14, 0, 0, 0, "white")
	local RAINBOW = { "berry_red", "orange", "yellow", "green", "blue", "purple" }
	for arm = 0, 5 do
		for i = 1, 5 do
			local rr = 0.08 + 0.09 * i
			local ang = arm * PI / 3 + i * 0.5
			fput(api, A, P, 0.2, 0.15, 0.06, cos(ang) * rr, sin(ang) * rr, 0.08, RAINBOW[arm + 1], ANG(0, 0, ang + PI / 2))
		end
	end
	fdisc(api, A, P, 0.22, 0.1, 0, 0, 0.1, c)
	fput(api, A, P, 0.08, 0.08, 0.06, 0, 0, 0.14, a)
	fput(api, A, P, 0.1, 0.1, 0.06, -0.24, 0.3, 0.12, "white")
end

-- a balloon floating beside the head on a string in the accent, a knot and a shine; low and far enough out that the
-- customization screen's Hand tab shows it past the head (it floated out of that picture)
HAND.balloon = function(api, c, a, _ctx)
	local A = api.ARM_R
	local bx, by, bz = 2.4, 3.25, -0.1
	link(api, A, 1.02, 1.32, 0.3, 1.7, 2.1, 0.1, 0.1, a)
	link(api, A, 1.7, 2.1, 0.1, bx - 0.04, by - 0.52, bz, 0.1, a)
	api.ball(A, 0.95, bx, by, bz, c)
	api.ball(A, 0.82, bx, by + 0.16, bz, c)
	api.ball(A, 0.16, bx - 0.02, by - 0.5, bz, c)
	api.ball(A, 0.18, bx + 0.14, by + 0.28, bz + 0.34, "white")
end

-- a paper cone of flowers: pink and white blooms over green leaves, a ribbon round the wrap
HAND.bouquet = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.56, 0.22, 0.4, "white")
	fcyl(api, A, GRIP, 0.42, 0.22, 0.18, "white")
	fcyl(api, A, GRIP, 0.28, 0.25, -0.06, "white")
	fcyl(api, A, GRIP, 0.14, 0.2, -0.3, a)
	fcyl(api, A, GRIP, 0.45, 0.1, 0.22, c)
	for i, f in { { -0.16, 0.68, 0.05 }, { 0.17, 0.66, 0.08 }, { 0, 0.8, -0.1 }, { 0.02, 0.68, 0.2 }, { -0.14, 0.72, -0.18 } } do
		fball(api, A, GRIP, 0.34, f[1], f[2], f[3], if i == 2 or i == 5 then "white" else c)
	end
	for _, sx in { -1, 1 } do
		fput(api, A, GRIP_FACE, 0.28, 0.14, 0.1, sx * 0.34, 0.52, 0, a, ANG(0, 0, sx * 0.5))
	end
end

-- a black wand with a white tip and a big glowing star turned up toward the camera (and the customization screen's view:
-- faceBoth), two sparkles by it
HAND.magic_wand = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.13, 1.1, 0.3, a)
	fcyl(api, A, GRIP, 0.14, 0.16, 0.9, "white")
	local tip = GRIP * CFrame.new(0, 1.24, 0)
	local S = faceBoth(CFrame.new(tip.X, tip.Y, tip.Z) * ANG(0, PI / 4, 0) * ANG(-0.52, 0, 0))
	star(api, A, S, 0.22, 0.12, c, nil, true)
	fput(api, A, S, 0.14, 0.14, 0.1, 0.46, 0.32, 0, "white", DIAMOND)
	api.glow()
	fput(api, A, S, 0.12, 0.12, 0.1, -0.44, -0.2, 0, "white", DIAMOND)
	api.glow()
end

-- an open umbrella held out over the shoulder: a striped canopy, a tip, a shaft in the accent with a hooked handle
HAND.umbrella = function(api, c, a, _ctx)
	local A = api.ARM_R
	local F = CFrame.new(1.02, 1.25, 0.28) * ANG(-0.22, 0, -0.5)
	fcyl(api, A, F, 0.12, 2.5, 0.95, a)
	fput(api, A, F, 0.32, 0.12, 0.12, 0.12, -0.3, 0, a)
	fput(api, A, F, 0.12, 0.22, 0.12, 0.28, -0.2, 0, a)
	fcyl(api, A, F, 1.55, 0.12, 2.2, c)
	fcyl(api, A, F, 1.25, 0.14, 2.32, "white")
	fcyl(api, A, F, 0.92, 0.14, 2.44, c)
	fcyl(api, A, F, 0.52, 0.14, 2.56, "white")
	fball(api, A, F, 0.14, 0, 2.68, 0, a)
end

-- a teddy bear held up in front, facing out: body, a belly in the accent, head, ears, snout, eyes, feet, a bow
HAND.teddy_bear = function(api, c, a, _ctx)
	local A = api.ARM_R
	local F = CFrame.new(1.0, 1.25, 0.6) * ANG(0, 0.45, 0)
	fball(api, A, F, 0.6, 0, 0.3, 0, c)
	fball(api, A, F, 0.36, 0, 0.27, 0.18, a)
	fball(api, A, F, 0.55, 0, 0.8, 0, c)
	fball(api, A, F, 0.22, 0, 0.74, 0.25, a)
	fball(api, A, F, 0.1, 0, 0.77, 0.36, "ink")
	fput(api, A, F, 0.18, 0.1, 0.1, 0, 0.55, 0.26, "berry_red")
	for _, sx in { -1, 1 } do
		fball(api, A, F, 0.22, sx * 0.22, 1.03, -0.02, c)
		fput(api, A, F, 0.1, 0.1, 0.1, sx * 0.11, 0.88, 0.26, "ink")
		fball(api, A, F, 0.22, sx * 0.18, 0.06, 0.14, c)
	end
end

-- a long loaf held up: rounded ends, scoring in the accent, a paper wrap round the bottom
HAND.baguette = function(api, c, a, _ctx)
	local A = api.ARM_R
	fcyl(api, A, GRIP, 0.32, 1.6, 0.45, c)
	fball(api, A, GRIP, 0.32, 0, -0.35, 0, c)
	fball(api, A, GRIP, 0.32, 0, 1.25, 0, c)
	for _, s in { 0.42, 0.76, 1.08 } do
		fput(api, A, GRIP_FACE, 0.22, 0.1, 0.1, 0, s, 0.14, a, ANG(0, 0, 0.5))
	end
	fcyl(api, A, GRIP, 0.36, 0.35, 0, "white")
end

-- a takeaway cup, wider at the top: a sleeve in the accent, a lid, two puffs of steam
HAND.coffee_cup = function(api, c, a, _ctx)
	local A = api.ARM_R
	local x, y, z = 1.0, 1.45, 0.52
	api.cyl(A, 0.38, 0.28, x, y - 0.14, z, c)
	api.cyl(A, 0.46, 0.3, x, y + 0.13, z, c)
	api.cyl(A, 0.5, 0.24, x, y + 0.02, z, a)
	api.cyl(A, 0.52, 0.1, x, y + 0.33, z, c)
	api.cyl(A, 0.4, 0.1, x, y + 0.42, z, c)
	api.ball(A, 0.16, x + 0.05, y + 0.62, z, "white")
	api.ball(A, 0.12, x - 0.04, y + 0.8, z, "white")
end

------------------------------------------------------------------ the Weekly Cup's looks: animation and shapes

-- The Weekly Cup's 18 looks (the bakery's weekly prizes) move: Api.anim gives a group of parts a loop of frames, each a move of
-- their rest CFrames in rig space (CharacterModels.pose steps them 7 a second, each part through its own number of
-- frames; nested groups multiply). A part leaves the picture by moving inside a solid part of its bone (HIDE_*); the
-- still pictures (Shop, customization screen, rewards) show the rest pose, every part in place.
local FACE_CAM = ANG(0, PI / 4, 0) -- a flat thing turned to face the world's camera (from the front-right)
local HIDE_HEAD = Vector3.new(0, 3.5, 0) -- inside the head
local HIDE_ROOT = Vector3.new(0, 1.75, 0) -- inside the torso
local HIDE_ARM = Vector3.new(1, 1.85, 0) -- inside the right arm (parts under 0.45 across)

-- a sine over a loop of n frames: frame f's value, `amp` high, starting at `phase`
local function osc(f: number, n: number, amp: number, phase: number?): number
	return amp * sin(2 * PI * (f - 1) / n + (phase or 0))
end

-- n frames turning about F's origin by at(f)'s angles about F's X, Y and Z axes
local function turnF(F: CFrame, n: number, at: (number) -> (number, number, number)): { CFrame }
	local inv = F:Inverse()
	local out: { CFrame } = table.create(n)
	for f = 1, n do
		local rx, ry, rz = at(f)
		out[f] = F * ANG(rx, ry, rz) * inv
	end
	return out
end

-- n frames turning `turn` radians in all round F's Y axis (spinF) or its Z axis (rollF)
local function spinF(F: CFrame, n: number, turn: number): { CFrame }
	return turnF(F, n, function(f)
		return 0, turn * (f - 1) / n, 0
	end)
end

local function rollF(F: CFrame, n: number, turn: number): { CFrame }
	return turnF(F, n, function(f)
		return 0, 0, turn * (f - 1) / n
	end)
end

-- n frames moving by at(f) (rig space)
local function moveF(n: number, at: (number) -> Vector3): { CFrame }
	local out: { CFrame } = table.create(n)
	for f = 1, n do
		out[f] = CFrame.new(at(f))
	end
	return out
end

-- a part drawn at path[k + 1] stepping one point along the path a frame, round and round (steam rising, a drop
-- falling, a heart floating up); a point inside a solid part takes it out of sight
local function alongF(path: { Vector3 }, k: number): { CFrame }
	local n = #path
	local rest = path[k % n + 1]
	local out: { CFrame } = table.create(n)
	for f = 1, n do
		out[f] = CFrame.new(path[(f - 1 + k) % n + 1] - rest)
	end
	return out
end

-- a twinkle at S: per frame of `pat`, "1" in place, "2" turned an eighth about S's Z, "0" hidden at `hide`
local function twinkleF(S: CFrame, hide: Vector3, pat: string): { CFrame }
	local out: { CFrame } = table.create(#pat)
	local turned = S * ANG(0, 0, PI / 4) * S:Inverse()
	local gone = CFrame.new(hide - S.Position)
	for f = 1, #pat do
		local ch = string.sub(pat, f, f)
		out[f] = if ch == "0" then gone elseif ch == "2" then turned else CFrame.identity
	end
	return out
end

-- a right triangle in F's XY plane, t thick, legs w (x) and h (y), its right angle bottom right (`flip`: bottom
-- left), its box centred at (dx, dy, dz): a Wedge, whose triangle lies in its YZ plane, turned side on
local function tri(api: Api, bone: number, F: CFrame, w: number, h: number, t: number, dx: number, dy: number, dz: number, color: string, flip: boolean?)
	fput(api, bone, F, t, h, w, dx, dy, dz, color, if flip then ANG(0, -PI / 2, 0) else ANG(0, PI / 2, 0), "Wedge")
end

-- a point up F's Y: a triangle w across the base, h tall (the right half h2: a broken, jagged tip), its box
-- centred at (dx, dy, dz)
local function spike(api: Api, bone: number, F: CFrame, w: number, h: number, t: number, dx: number, dy: number, dz: number, color: string, h2: number?)
	tri(api, bone, F, w / 2, h, t, dx - w / 4, dy, dz, color)
	local hr = h2 or h
	tri(api, bone, F, w / 2, hr, t, dx + w / 4, dy - (h - hr) / 2, dz, color, true)
end

-- a flat band w wide and t thick in F's XY plane from (x1, y1) to (x2, y2): ribbons, rainbow bands
local function strip(api: Api, bone: number, F: CFrame, x1: number, y1: number, x2: number, y2: number, w: number, t: number, color: string)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	fput(api, bone, F, len + w * 0.4, w, t, (x1 + x2) / 2, (y1 + y2) / 2, 0, color, ANG(0, 0, math.atan2(dy, dx)))
end

-- a ring of n blocks round F's Y axis, radius r, each h tall and d deep (`lit`: glowing)
local function ring(api: Api, bone: number, F: CFrame, r: number, n: number, h: number, d: number, color: string, lit: boolean?)
	local len = 2 * r * math.tan(PI / n) + 0.04
	for k = 0, n - 1 do
		local ang = k * 2 * PI / n
		fput(api, bone, F, len, h, d, cos(ang) * r, 0, sin(ang) * r, color, ANG(0, PI / 2 - ang, 0))
		if lit then
			api.glow()
		end
	end
end

-- a ring of n blocks in F's XY plane (facing its Z), radius r, w wide and t thick
local function hoop(api: Api, bone: number, F: CFrame, r: number, n: number, w: number, t: number, color: string, lit: boolean?)
	local len = 2 * r * math.tan(PI / n) + 0.04
	for k = 0, n - 1 do
		local ang = k * 2 * PI / n
		fput(api, bone, F, len, w, t, cos(ang) * r, sin(ang) * r, 0, color, ANG(0, 0, ang + PI / 2))
		if lit then
			api.glow()
		end
	end
end

-- a four-pointed glint at S (facing its Z): two thin glowing bars crossed
local function sparkle(api: Api, bone: number, S: CFrame, len: number, color: string)
	fput(api, bone, S, len, len * 0.3, 0.06, 0, 0, 0, color)
	api.glow()
	fput(api, bone, S, len * 0.3, len, 0.06, 0, 0, 0, color)
	api.glow()
end

-- a glint at (x, y, z) facing the camera that twinkles by `pat` (twinkleF), hidden at `hide` between
local function glint(api: Api, bone: number, x: number, y: number, z: number, len: number, hide: Vector3, pat: string, color: string?)
	local from = api.count()
	local S = CFrame.new(x, y, z) * FACE_CAM
	sparkle(api, bone, S, len, color or "white")
	api.anim(from, twinkleF(S, hide, pat))
end

-- a wing's flap: n frames turning the wing (frame W at its root) up and down about its Z axis by `amp` (and back
-- and forth about its Y axis by `sweep`), `phase` along the loop
local function flapF(W: CFrame, sx: number, n: number, amp: number, sweep: number, phase: number?): { CFrame }
	return turnF(W, n, function(f)
		return 0, sx * osc(f, n, sweep, (phase or 0) - PI / 2), sx * osc(f, n, amp, phase)
	end)
end

------------------------------------------------------------------ the Weekly Cup's hats

local BOB8 = { 0, 0.06, 0.11, 0.14, 0.11, 0.06, 0, -0.04 } -- a gentle float up and down over 8 frames

-- Cloud Cup: a halo floating over the head, tipped to the camera: a glowing sky-blue ring with three cream puffs
-- (golden choux, a cream cap, a pink sugar pearl) and three little clouds (pink under) sitting round it. It bobs while
-- the puffs go round (a third of a turn a loop: the pattern repeats), and three glints twinkle by it in turn.
HAT.dream_puff_halo = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local F = CFrame.new(0, t + 0.82, -0.05) * ANG(0.26, 0, 0)
	local from = api.count()
	ring(api, H, F, 0.98, 12, 0.14, 0.2, "sky_day", true)
	for k = 0, 5 do
		local ang = k * PI / 3 + PI / 6
		local x, z = cos(ang) * 0.98, sin(ang) * 0.98
		if k % 2 == 0 then
			fball(api, H, F, 0.6, x, 0.1, z, "sponge")
			fball(api, H, F, 0.48, x, 0.34, z, "cream")
			fball(api, H, F, 0.18, x, 0.6, z, a)
		else
			local tx, tz = -sin(ang) * 0.27, cos(ang) * 0.27
			fball(api, H, F, 0.58, x, 0.16, z, c)
			fball(api, H, F, 0.42, x + tx, 0.08, z + tz, c)
			fball(api, H, F, 0.42, x - tx, 0.2, z - tz, "plate_white")
			fball(api, H, F, 0.32, x, -0.06, z, a)
		end
	end
	local inv = F:Inverse()
	local frames: { CFrame } = table.create(8)
	for f = 1, 8 do
		frames[f] = CFrame.new(0, BOB8[f], 0) * F * ANG(0, 2 * PI / 3 * (f - 1) / 8, 0) * inv
	end
	api.anim(from, frames)
	glint(api, H, -1.3, t + 1.2, 0.35, 0.42, HIDE_HEAD, "12100000")
	glint(api, H, 1.28, t + 0.62, 0.55, 0.38, HIDE_HEAD, "00012100")
	glint(api, H, 0.5, t + 1.62, 0.25, 0.34, HIDE_HEAD, "10000012")
end

-- Taffy Cup (bottom 4.3): a gold crown with caramel poured over its top and running down its sides in drips, a
-- caramel swirl topped with a wrapped taffy sweet, seven points tipped with caramel drops, an amber gem in front.
-- Drops form on three of the drips, fall and are gone (into the band) before the next forms; the gem glints.
HAT.caramel_drip_crown = function(api, c, a, _ctx)
	local H = api.HEAD
	local y0, w, z0 = 4.3, 2.26, -0.03
	local half = w / 2
	local top = y0 + 0.5
	api.add(H, w, 0.5, w, 0, y0 + 0.25, z0, "gold")
	api.add(H, w + 0.06, 0.1, w + 0.06, 0, y0 + 0.05, z0, "plate_gold")
	api.add(H, w + 0.06, 0.12, w + 0.06, 0, top + 0.02, z0, c)
	api.cyl(H, 1.5, 0.24, 0, top + 0.18, z0, "oven_glow")
	api.cyl(H, 1.06, 0.24, 0, top + 0.4, z0, c)
	api.cyl(H, 0.62, 0.22, 0, top + 0.6, z0, "oven_glow")
	-- the wrapped taffy on the swirl: a pink sweet with a cream stripe and twisted ends
	api.add(H, 0.56, 0.34, 0.34, 0, top + 0.86, z0, a, nil, "Cylinder")
	api.add(H, 0.08, 0.36, 0.36, 0, top + 0.86, z0, "cream", nil, "Cylinder")
	for _, sx in { -1, 1 } do
		api.add(H, 0.22, 0.3, 0.3, sx * 0.37, top + 0.86, z0, a, ANG(PI / 4, 0, 0))
	end
	-- the points: three in front, one a side, two behind, each tipped with a caramel drop
	local e = half - 0.06
	-- { x, z, facing, width, height }
	local pts = {
		{ 0, e, 0, 0.76, 1.1 },
		{ -0.7, e, 0, 0.58, 0.82 },
		{ 0.7, e, 0, 0.58, 0.82 },
		{ e, 0, PI / 2, 0.6, 0.88 },
		{ -e, 0, -PI / 2, 0.6, 0.88 },
		{ -0.5, -e, PI, 0.58, 0.8 },
		{ 0.5, -e, PI, 0.58, 0.8 },
	}
	for _, p in pts do
		local pw, ph = p[4], p[5]
		local F = CFrame.new(p[1], top, z0 + p[2]) * ANG(0, p[3], 0)
		spike(api, H, F, pw, ph, 0.12, 0, ph / 2 + 0.04, 0, "gold")
		fball(api, H, F, 0.26, 0, ph + 0.1, 0, c)
	end
	-- the amber gem in its setting
	disc(api, H, 0.52, 0.06, 0, y0 + 0.26, z0 + half + 0.02, "plate_gold")
	disc(api, H, 0.36, 0.08, 0, y0 + 0.26, z0 + half + 0.06, "r_legend")
	api.glow()
	-- the drips over the band (front, the camera's side, the other side): a run and a round end
	local fz, sxf = z0 + half + 0.03, half + 0.03
	for _, d in { { -0.42, 0.42 }, { 0.42, 0.24 }, { 0.86, 0.38 } } do
		api.add(H, 0.22, d[2], 0.06, d[1], top - d[2] / 2 + 0.06, fz, c)
		api.ball(H, 0.24, d[1], top - d[2] + 0.06, fz + 0.02, c)
	end
	for _, d in { { 0.62, 0.36 }, { -0.4, 0.22 } } do
		api.add(H, 0.06, d[2], 0.22, sxf, top - d[2] / 2 + 0.06, d[1], c)
		api.ball(H, 0.24, sxf + 0.02, top - d[2] + 0.06, d[1], c)
	end
	-- falling drops: under the front right drip, the side's front one and the front left one
	-- { across the face, length of its drip, phase, on the side }
	local falls: { { any } } = { { 0.86, 0.38, 0, false }, { 0.62, 0.36, 3, true }, { -0.42, 0.42, 5, false } }
	for _, d in falls do
		local x, y, side = d[1] :: number, top - (d[2] :: number) + 0.06, d[4] :: boolean
		local function at(dy: number): Vector3
			return if side then Vector3.new(sxf + 0.06, y + dy, x) else Vector3.new(x, y + dy, fz + 0.05)
		end
		local path = { at(-0.08), at(-0.18), at(-0.36), at(-0.64), at(-0.98), HIDE_HEAD, HIDE_HEAD, at(0.04) }
		local from = api.count()
		local k = d[3] :: number
		local p0 = path[k % 8 + 1]
		api.ball(H, 0.24, p0.X, p0.Y, p0.Z, "oven_glow")
		api.anim(from, alongF(path, k))
	end
	glint(api, H, 0.1, y0 + 0.34, z0 + half + 0.14, 0.38, HIDE_HEAD, "12000000")
end

-- Crunch Cup (bottom 4.35): a band of biscuit trimmed in gold with amber brittle set in it, and wafer spires rising
-- round it to a peak at the front, ringed with baked lines, the front ones tipped with gold points, the tallest crowned
-- with an amber star. The star turns, three amber shards go round the crown and the brittle glints piece by piece.
HAT.wafer_spire_crown = function(api, c, a, _ctx)
	local H = api.HEAD
	local y0, w, z0 = 4.35, 2.2, -0.03
	local half = w / 2
	local top = y0 + 0.46
	api.add(H, w, 0.46, w, 0, y0 + 0.23, z0, "floor_b")
	api.add(H, w + 0.06, 0.09, w + 0.06, 0, y0 + 0.04, z0, a)
	api.add(H, w + 0.06, 0.09, w + 0.06, 0, top - 0.03, z0, a)
	local fz = z0 + half + 0.02
	for _, x in { -0.62, 0, 0.62 } do
		api.add(H, 0.28, 0.28, 0.08, x, y0 + 0.23, fz + 0.02, "r_legend", DIAMOND)
		api.glow()
	end
	-- the spires: { x, z, height, baked lines, a gold point (else a gold ball) }
	local e = half - 0.2
	local spires: { { any } } = {
		{ -0.56, e, 1.25, 2, true },
		{ 0.56, e, 1.25, 2, true },
		{ -e, e, 0.9, 1, false },
		{ e, e, 0.9, 1, false },
		{ e, -0.25, 1.05, 1, false },
		{ -e, -0.25, 1.05, 1, false },
		{ 0, -e, 0.95, 1, false },
	}
	for _, s in spires do
		local x, z, h, n = s[1] :: number, z0 + s[2] :: number, s[3] :: number, s[4] :: number
		api.add(H, 0.32, h, 0.32, x, top + h / 2, z, c)
		for k = 1, n do
			api.add(H, 0.35, 0.07, 0.35, x, top + h * k / (n + 1), z, "wood")
		end
		if s[5] then
			spike(api, H, CFrame.new(x, top + h, z) * FACE_CAM, 0.3, 0.36, 0.12, 0, 0.18, 0, a)
		else
			api.ball(H, 0.24, x, top + h + 0.08, z, a)
		end
	end
	-- the tallest in front, and its amber star turning
	local cz = z0 + e
	api.add(H, 0.4, 1.45, 0.4, 0, top + 0.725, cz, c)
	for _, f in { 0.33, 0.67 } do
		api.add(H, 0.43, 0.07, 0.43, 0, top + 1.45 * f, cz, "wood")
	end
	api.cyl(H, 0.34, 0.12, 0, top + 1.49, cz, a)
	local S = CFrame.new(0, top + 1.88, cz)
	local from = api.count()
	star(api, H, S, 0.24, 0.12, "r_legend", "yellow", true)
	api.anim(from, spinF(S, 8, PI))
	-- three amber shards going round
	local O = CFrame.new(0, top + 0.4, z0) * ANG(0.18, 0, 0.1)
	from = api.count()
	for k = 0, 2 do
		local ang = k * 2 * PI / 3 + 0.4
		fput(api, H, O, 0.3, 0.3, 0.1, cos(ang) * 1.45, 0, sin(ang) * 1.45, "r_legend", ANG(0, -ang, PI / 4))
		api.glow()
	end
	api.anim(from, spinF(O, 8, -2 * PI / 3))
	glint(api, H, -0.62, y0 + 0.3, fz + 0.1, 0.34, HIDE_HEAD, "21000000")
	glint(api, H, 0.62, y0 + 0.3, fz + 0.1, 0.34, HIDE_HEAD, "00002100")
end

-- Zen Tea Cup (bottom 4.4): a porcelain teacup on its saucer worn as a hat: a jade band and saucer rim, gold lines, a
-- gold lip, matcha with a little foam and a floating pink petal, a lotus painted on the side, a tea tag hanging over
-- the rim and a handle toward the camera. Steam curls up out of it in three wisps of puffs that rise, drift and go.
HAT.steaming_teacup_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	local y0, z0 = 4.4, -0.03
	api.cyl(H, 2.5, 0.08, 0, y0 + 0.04, z0, c)
	api.cyl(H, 2.36, 0.12, 0, y0 + 0.12, z0, "plate_white")
	api.cyl(H, 1.2, 0.2, 0, y0 + 0.26, z0, "plate_white")
	api.cyl(H, 1.5, 0.44, 0, y0 + 0.56, z0, "plate_white")
	api.cyl(H, 1.56, 0.16, 0, y0 + 0.5, z0, c)
	api.cyl(H, 1.58, 0.04, 0, y0 + 0.6, z0, "plate_gold")
	api.cyl(H, 1.8, 0.48, 0, y0 + 0.98, z0, "plate_white")
	api.cyl(H, 1.86, 0.08, 0, y0 + 1.22, z0, "plate_gold")
	api.cyl(H, 1.68, 0.08, 0, y0 + 1.26, z0, "green")
	api.cyl(H, 0.8, 0.04, 0.18, y0 + 1.3, z0 + 0.12, "grass")
	api.ball(H, 0.22, -0.38, y0 + 1.3, z0 + 0.32, a)
	-- the handle toward the camera
	api.add(H, 0.4, 0.14, 0.2, 1.02, y0 + 1.02, z0, "plate_white")
	api.add(H, 0.34, 0.14, 0.2, 0.9, y0 + 0.48, z0, "plate_white")
	api.add(H, 0.14, 0.68, 0.2, 1.2, y0 + 0.75, z0, "plate_white")
	-- a lotus painted on the side the camera sees: three petals and a gold heart
	local L = CFrame.new(0, y0 + 0.98, z0) * ANG(0, 0.62, 0) * CFrame.new(0, 0, 0.88)
	fball(api, H, L, 0.24, 0, 0.07, 0, a)
	fball(api, H, L, 0.2, -0.15, -0.02, -0.02, a)
	fball(api, H, L, 0.2, 0.15, -0.02, -0.02, a)
	fball(api, H, L, 0.12, 0, -0.07, 0.07, "gold")
	-- the tea tag over the rim at the front
	local tx, tz = -0.42, z0 + 0.8
	link(api, H, tx, y0 + 1.26, tz - 0.12, tx - 0.04, y0 + 0.86, tz + 0.08, 0.04, "cream")
	api.add(H, 0.28, 0.3, 0.05, tx - 0.05, y0 + 0.7, tz + 0.1, c)
	api.add(H, 0.14, 0.12, 0.06, tx - 0.05, y0 + 0.72, tz + 0.11, "cream")
	-- three wisps of steam: puffs rising out of the tea in a curl, hidden in the cup between
	local wisps = { { 0.32, 0.2, 0 }, { -0.34, -0.3, 2.1 }, { 0.05, -0.05, 4.2 } }
	for wsp, wd in wisps do
		local x0, z1, ph = wd[1], z0 + wd[2], wd[3]
		local path: { Vector3 } = { Vector3.new(x0, y0 + 1.0, z1) }
		for f = 1, 7 do
			path[f + 1] = Vector3.new(x0 + 0.26 * sin(f * 0.9 + ph), y0 + 1.24 + 0.15 * f, z1 + 0.16 * cos(f * 0.9 + ph))
		end
		for i, k in { (wsp - 1) % 2 + 1, (wsp - 1) % 2 + 4 } do
			local from = api.count()
			local p0 = path[k + 1]
			api.ball(H, 0.64 - i * 0.1, p0.X, p0.Y, p0.Z, if (i + wsp) % 2 == 0 then "plate_white" else "white")
			api.anim(from, alongF(path, k))
		end
	end
end

-- Sweetheart Cup: a gold tiara: a gold arch over a big ruby heart framed in gold at its middle, pink hearts and gold
-- diamonds stepping down its sides, pearls, and chocolate bonbons drizzled pink on its ends. The big heart beats
-- (lub-dub: a bigger heart shows for two frames of seven), little hearts float up off it, and a glint twinkles.
HAT.bonbon_tiara = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local z = 0.86
	api.add(H, 1.84, 0.2, 0.2, 0, t + 0.08, z, "gold")
	for _, sx in { -1, 1 } do
		api.add(H, 0.8, 0.2, 0.2, sx * 1.0, t + 0.07, 0.52, "gold", ANG(0, sx * 1.17, 0))
		heart(api, H, CFrame.new(sx * 0.68, t + 0.48, z + 0.02), 0.62, 0.12, a)
		api.add(H, 0.24, 0.24, 0.1, sx * 0.98, t + 0.3, z, "gold", DIAMOND)
		api.ball(H, 0.14, sx * 0.36, t + 0.22, z + 0.08, "white")
		-- bonbons: one on the front's end, one on the side
		api.ball(H, 0.4, sx * 1.02, t + 0.24, 0.66, "chocolate")
		api.add(H, 0.42, 0.07, 0.12, sx * 1.02, t + 0.3, 0.81, a, ANG(0, 0, 0.3))
		api.ball(H, 0.14, sx * 1.02, t + 0.47, 0.66, "berry_red")
	end
	-- the gold arch over the heart
	local Ar = CFrame.new(0, t + 0.84, z - 0.06)
	for k = 0, 4 do
		local ang = k * PI / 4
		fput(api, H, Ar, 0.46, 0.11, 0.1, cos(ang) * 0.74, sin(ang) * 0.74, 0, "gold", ANG(0, 0, ang + PI / 2))
	end
	api.add(H, 0.24, 0.24, 0.1, 0, t + 1.66, z - 0.06, a, DIAMOND)
	api.glow()
	-- the heart: gold frame, ruby, a glint; the bigger one shows on the beats, inside the head between
	local F = CFrame.new(0, t + 0.82, z + 0.04)
	heart(api, H, F * CFrame.new(0, 0, -0.03), 1.0, 0.1, "gold")
	heart(api, H, F, 0.82, 0.14, c)
	fball(api, H, F, 0.13, -0.18, 0.13, 0.08, "white")
	local from = api.count()
	heart(api, H, F * CFrame.new(0, 0.03, 0.03), 1.26, 0.1, "gold")
	heart(api, H, F * CFrame.new(0, 0.03, 0.06), 1.08, 0.14, c)
	fball(api, H, F, 0.16, -0.24, 0.19, 0.14, "white")
	local hide = CFrame.new(0, -1.75, -0.1)
	local beat = { CFrame.identity, hide, CFrame.identity, hide, hide, hide, hide }
	api.anim(from, beat)
	-- two little hearts floating up off it
	for i, col in { "r_mythic", a } do
		local sx = if i == 1 then -1 else 1
		local path: { Vector3 } = { HIDE_HEAD, HIDE_HEAD }
		for f = 1, 6 do
			table.insert(path, Vector3.new(sx * (0.34 + 0.09 * f) + 0.07 * sin(f * 1.4), t + 1.1 + 0.2 * f, z + 0.06))
		end
		local k = if i == 1 then 3 else 5
		local from2 = api.count()
		local p0 = path[k % #path + 1]
		heart(api, H, CFrame.new(p0), 0.34, 0.08, col)
		api.anim(from2, alongF(path, k))
	end
	glint(api, H, -0.56, t + 1.4, z + 0.12, 0.36, HIDE_HEAD, "1200121")
end

-- Sugar Rush Cup: a purple crown trimmed in yellow, seven points in every colour of the rainbow tipped with white
-- gumballs, a glowing star over it, and a storm of rainbow sprinkles round it: two tilted rings of six whirling
-- opposite ways (half a turn a loop: three colours twice over), while the star turns.
HAT.sprinkle_storm_crown = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local z0 = -0.05
	api.add(H, 1.84, 0.46, 1.84, 0, t + 0.2, z0, c)
	api.add(H, 1.9, 0.09, 1.9, 0, t + 0.42, z0, a)
	api.add(H, 1.9, 0.09, 1.9, 0, t + 0.02, z0, a)
	local cols = { "r_legend", "berry_red", "r_uncommon", "r_rare", "r_mythic", "yellow", "r_epic" }
	-- { x, z, facing, height }
	local pts = { { 0, 0.88, 0, 0.95 }, { -0.58, 0.88, 0, 0.68 }, { 0.58, 0.88, 0, 0.68 }, { 0.88, 0, PI / 2, 0.75 }, { -0.88, 0, -PI / 2, 0.75 }, { -0.44, -0.88, PI, 0.65 }, { 0.44, -0.88, PI, 0.65 } }
	for i, p in pts do
		local F = CFrame.new(p[1], t + 0.46, z0 + p[2]) * ANG(0, p[3], 0)
		spike(api, H, F, 0.5, p[4], 0.12, 0, p[4] / 2, 0, cols[i])
		fball(api, H, F, 0.24, 0, p[4] + 0.06, 0, "white")
	end
	for i, x in { -0.52, 0, 0.52 } do
		disc(api, H, 0.22, 0.08, x, t + 0.22, z0 + 0.94, cols[i + 2])
	end
	api.add(H, 0.08, 0.22, 0.22, 0.94, t + 0.22, z0 + 0.3, "r_mythic", ANG(PI / 4, 0, 0))
	api.add(H, 0.08, 0.22, 0.22, 0.94, t + 0.22, z0 - 0.4, "r_rare", ANG(PI / 4, 0, 0))
	-- the star over it, turning
	local S = CFrame.new(0, t + 1.78, z0 + 0.2) * FACE_CAM
	local from = api.count()
	star(api, H, S, 0.26, 0.12, a, "white", true)
	api.anim(from, spinF(S, 8, PI))
	-- the storm: two rings of eight sprinkles, four colours twice over each
	type Storm = { O: CFrame, r: number, cols: { string }, turn: number }
	local rings: { Storm } = {
		{ O = CFrame.new(0, t + 0.46, z0) * ANG(0.32, 0, 0.16), r = 1.38, cols = { "r_mythic", "yellow", "r_rare" }, turn = PI },
		{ O = CFrame.new(0, t + 1.02, z0) * ANG(-0.26, 0, -0.2), r = 1.16, cols = { "r_legend", "r_uncommon", "r_epic" }, turn = -PI },
	}
	for _, rg in rings do
		local O, r, rc = rg.O, rg.r, rg.cols
		from = api.count()
		for k = 0, 5 do
			local ang = k * PI / 3
			fput(api, H, O, 0.42, 0.12, 0.12, cos(ang) * r, 0.05 * sin(ang * 2), sin(ang) * r, rc[k % 3 + 1], ANG(0, PI / 2 - ang, 0.35))
		end
		api.anim(from, spinF(O, 8, rg.turn))
	end
end

------------------------------------------------------------------ the Weekly Cup's back pieces

-- the Weekly Cup's wings rise high and spread wide from the upper back, so they show over the head and beside it from
-- the world's camera (a wing that sweeps back hides behind the body), and lean back, clear of the back of the head
local function bigWing(sx: number): CFrame
	return CFrame.new(sx * 0.3, 2.3, -0.66) * ANG(0, sx * 0.16, 0) * ANG(-0.26, 0, 0)
end

-- Cloud Cup: wings of cloud: an arm of big white puffs curving up past the head, a row of paler ones under it, a pink
-- fringe of little puffs along the bottom. They flap; a wisp of cloud drifts off each tip; glints twinkle in them.
local CLOUD_WING: { { number } } = {
	-- { out, up, across, tone (1 the main colour, 2 pale white, 3 the accent) }
	{ 0.2, 0.15, 0.68, 1 },
	{ 0.6, 0.52, 0.8, 1 },
	{ 1.0, 0.94, 0.8, 1 },
	{ 1.36, 1.4, 0.74, 1 },
	{ 1.66, 1.86, 0.64, 1 },
	{ 1.88, 2.28, 0.52, 1 },
	{ 2.0, 2.62, 0.38, 1 },
	{ 0.52, -0.2, 0.62, 2 },
	{ 0.96, 0.18, 0.68, 2 },
	{ 1.38, 0.62, 0.66, 2 },
	{ 1.76, 1.08, 0.58, 2 },
	{ 2.06, 1.54, 0.48, 2 },
	{ 2.24, 1.96, 0.36, 2 },
	{ 0.76, -0.54, 0.44, 3 },
	{ 1.2, -0.2, 0.48, 3 },
	{ 1.64, 0.2, 0.46, 3 },
	{ 2.04, 0.64, 0.42, 3 },
	{ 2.3, 1.1, 0.34, 3 },
}
BACK.cloud_nine_wings = function(api, c, a, _ctx)
	local R = api.ROOT
	for _, sx in { -1, 1 } do
		local W = bigWing(sx)
		local from = api.count()
		for _, p in CLOUD_WING do
			local tone = p[4]
			local col = if tone == 1 then c elseif tone == 2 then "plate_white" else a
			fball(api, R, W, p[3], sx * p[1] * 0.9, p[2], if tone == 2 then 0.12 else 0, col)
		end
		-- the wisp: out of the tip puff, up and away, back inside it
		local function wp(x: number, y: number): Vector3
			return (W * CFrame.new(sx * x * 0.9, y, 0)).Position
		end
		local tip = wp(2.0, 2.62)
		local out = { tip, tip, wp(2.14, 2.84), wp(2.28, 3.02), wp(2.4, 3.18), wp(2.48, 3.32), tip, tip }
		-- (the two wisps half a loop apart, each resting inside its tip puff)
		local path: { Vector3 } = table.create(8)
		for f = 1, 8 do
			path[f] = out[(f - 1 + (if sx > 0 then 0 else 4)) % 8 + 1]
		end
		local w0 = api.count()
		api.ball(R, 0.28, tip.X, tip.Y, tip.Z, c)
		api.anim(w0, alongF(path, 0))
		local g = wp(1.5, 1.45) + Vector3.new(0, 0, 0.45)
		glint(api, R, g.X, g.Y, g.Z, 0.38, HIDE_ROOT, if sx > 0 then "02100000" else "00002100")
		api.anim(from, flapF(W, sx, 8, 0.16, 0.1))
	end
end

-- Taffy Cup: wings of pulled taffy ribbon: a long loop up past the head and one out to the side, striped pink, cream
-- and caramel, a ribbon tail with a notched end, knotted at the spine by a wrapped taffy sweet. The loops flutter a
-- beat apart and the tails wave.
BACK.taffy_ribbon_wings = function(api, c, a, _ctx)
	local R = api.ROOT
	local tones = { c, "cream", a }
	-- a loop: { centre out, centre up, half length, half width, tilt, segments, flutter, phase }
	local loops = { { 0.95, 1.32, 1.42, 0.5, 1.0, 9, 0.12, 0 }, { 1.22, 0.3, 1.02, 0.4, 0.22, 6, 0.14, -1.1 } }
	for _, sx in { -1, 1 } do
		local W = bigWing(sx)
		for _, lp in loops do
			local cx, cy, rx, ry, tilt, n = lp[1], lp[2], lp[3], lp[4], lp[5], lp[6]
			local from = api.count()
			local function pt(th: number): (number, number)
				local ex, ey = rx * cos(th), ry * sin(th)
				return sx * (cx + ex * cos(tilt) - ey * sin(tilt)), cy + ex * sin(tilt) + ey * cos(tilt)
			end
			for k = 0, n - 1 do
				local x1, y1 = pt(2 * PI * k / n)
				local x2, y2 = pt(2 * PI * (k + 1) / n)
				strip(api, R, W, x1, y1, x2, y2, 0.3, 0.12, tones[k % 3 + 1])
			end
			api.anim(from, flapF(W, sx, 8, lp[7], 0.06, lp[8]))
		end
		-- the tail: two lengths down and out, and a notched end, waving
		local tail = { { 0.14, -0.12 }, { 0.5, -0.78 }, { 0.42, -1.36 } }
		for k = 1, 2 do
			local p, q = tail[k], tail[k + 1]
			local from = api.count()
			strip(api, R, W, sx * p[1], p[2], sx * q[1], q[2], 0.28, 0.12, tones[k])
			if k == 2 then
				local N = W * CFrame.new(sx * q[1], q[2] - 0.2, 0)
				tri(api, R, N, 0.16, 0.32, 0.12, -0.08, 0, 0, c, true)
				tri(api, R, N, 0.16, 0.32, 0.12, 0.08, 0, 0, c)
			end
			local P = W * CFrame.new(sx * p[1], p[2], 0)
			api.anim(from, turnF(P, 8, function(f)
				return 0, 0, sx * osc(f, 8, 0.14 + 0.06 * k, -0.9 * k)
			end))
		end
	end
	-- the knot: a wrapped taffy across the spine, a cream stripe either side, twisted ends
	local from = api.count()
	api.add(R, 0.8, 0.48, 0.48, 0, 2.3, -0.82, c, nil, "Cylinder")
	for _, sx in { -1, 1 } do
		api.add(R, 0.08, 0.5, 0.5, sx * 0.2, 2.3, -0.82, "cream", nil, "Cylinder")
		api.add(R, 0.24, 0.36, 0.36, sx * 0.52, 2.3, -0.82, a, ANG(PI / 4, 0, 0))
	end
	api.anim(from, turnF(CFrame.new(0, 2.3, -0.82), 8, function(f)
		return 0, 0, osc(f, 8, 0.08, 0.5)
	end))
end

-- Crunch Cup: wings of amber brittle: four long broken shards fanning out of a slab at the spine, amber and darker
-- toffee by turns, a glassy streak down each, a nut set in each. They flap and fan open and shut; glints run over
-- their tips.
local SHARDS: { { number } } = {
	-- { angle out from straight up, length, base width, the jagged half's share of the length }
	{ 0.16, 2.6, 0.8, 0.8 },
	{ 0.56, 2.9, 0.92, 0.86 },
	{ 0.98, 2.5, 0.84, 0.76 },
	{ 1.42, 1.9, 0.7, 0.82 },
}
BACK.brittle_shard_wings = function(api, c, a, _ctx)
	local R = api.ROOT
	for _, sx in { -1, 1 } do
		local W = bigWing(sx)
		for j, s in SHARDS do
			local from = api.count()
			local S = W * CFrame.new(sx * 0.15, -0.05, 0) * ANG(0, 0, -sx * s[1])
			local L, wd = s[2], s[3]
			local col = if j % 2 == 1 then c else "oven_glow"
			-- the jagged half faces outward on both wings
			if sx > 0 then
				spike(api, R, S, wd, L, 0.14, 0, L / 2 + 0.1, 0, col, L * s[4])
			else
				spike(api, R, S, wd, L * s[4], 0.14, 0, L * s[4] / 2 + 0.1, 0, col, L)
			end
			fput(api, R, S, 0.1, L * 0.5, 0.18, -sx * 0.08, L * 0.4, 0, a)
			fput(api, R, S, 0.2, 0.15, 0.2, sx * 0.1, L * 0.24, 0, if j % 2 == 1 then "chocolate" else "floor_a", ANG(0, 0, 0.7))
			api.anim(from, turnF(W, 8, function(f)
				return 0, sx * osc(f, 8, 0.08, -PI / 2), sx * (osc(f, 8, 0.12) + (j - 2.5) * osc(f, 8, 0.05, 0.6))
			end))
		end
		-- glints over the first and third shards' tips
		for gi, j in { 1, 3 } do
			local s = SHARDS[j]
			local tip = (W * CFrame.new(sx * 0.15, -0.05, 0) * ANG(0, 0, -sx * s[1]) * CFrame.new(0, s[2] * 0.8, 0.14)).Position
			local pat = if (gi + (if sx > 0 then 0 else 1)) % 2 == 0 then "21000000" else "00002100"
			glint(api, R, tip.X, tip.Y, tip.Z, 0.4, HIDE_ROOT, pat)
		end
	end
	-- the slab of brittle at the spine, nuts in it
	api.add(R, 1.0, 0.6, 0.24, 0, 2.28, -0.66, c)
	api.add(R, 0.2, 0.16, 0.28, -0.2, 2.38, -0.66, "chocolate", ANG(0, 0, 0.6))
	api.add(R, 0.18, 0.14, 0.28, 0.24, 2.16, -0.66, "floor_a", ANG(0, 0, -0.5))
end

-- Zen Tea Cup: a lotus aura behind the wearer: a glowing jade ring round the body and head, eight long pink petals
-- and cream ones between them radiating from a gold seed pod. It floats up and down, four bright beads go round
-- the ring, and jade motes rise beside the wearer.
BACK.lotus_aura = function(api, c, a, _ctx)
	local R = api.ROOT
	local cy = 3.05
	local C = CFrame.new(0, cy, -1.2) * ANG(-0.1, 0, 0)
	local from = api.count()
	hoop(api, R, C, 2.3, 12, 0.15, 0.12, c, true)
	for k = 0, 7 do
		local ang = k * PI / 4
		local P = C * ANG(0, 0, ang)
		spike(api, R, P, 0.96, 1.45, 0.1, 0, 1.72, 0, "pink")
		-- (the lower petals' streaks and cream petals would be behind the legs)
		if k < 3 or k > 5 then
			fput(api, R, P, 0.14, 0.92, 0.14, 0, 1.66, 0, "wall")
		end
		if k ~= 3 and k ~= 4 then
			fput(api, R, C * ANG(0, 0, ang + PI / 8), 0.58, 0.58, 0.12, 0, 1.32, 0.03, a, DIAMOND)
		end
	end
	disc(api, R, 1.1, 0.12, 0, cy, -1.2, "plate_gold")
	disc(api, R, 0.6, 0.16, 0, cy, -1.2, c)
	local bob = moveF(8, function(f)
		return Vector3.new(0, BOB8[f] * 0.8, 0)
	end)
	api.anim(from, bob)
	-- the beads going round the ring (a quarter turn a loop)
	from = api.count()
	for k = 0, 3 do
		local ang = k * PI / 2 + PI / 4
		fball(api, R, C, 0.32, cos(ang) * 2.3, sin(ang) * 2.3, 0.06, "cream")
		api.glow()
	end
	api.anim(from, rollF(C, 8, PI / 2))
	api.anim(from, bob)
	-- motes rising beside the wearer, out of sight in the torso between
	local motes = { { -1.4, 0.3, 0 }, { 1.5, 0.15, 3 }, { -1.0, -0.6, 5 } }
	for _, m in motes do
		local path: { Vector3 } = { HIDE_ROOT }
		for f = 1, 7 do
			path[f + 1] = Vector3.new(m[1] + 0.12 * sin(f * 1.1), 1.0 + 0.5 * f, m[2])
		end
		local k = m[3]
		local p0 = path[k % 8 + 1]
		local f0 = api.count()
		api.ball(R, 0.22, p0.X, p0.Y, p0.Z, c)
		api.glow()
		api.anim(f0, alongF(path, k))
	end
end

-- Sweetheart Cup: wings of hearts: a big ruby heart rising past the head and a smaller one out to the side each side,
-- points to the spine, rimmed in gold, pink hearts in them and a glint. They flap, the pink hearts beat (a bigger one
-- shows on each lub and dub), and little hearts float up off them.
BACK.heartbeat_wings = function(api, c, a, _ctx)
	local R = api.ROOT
	for _, sx in { -1, 1 } do
		local W = bigWing(sx)
		local from = api.count()
		for i, h in { { 1.1, 1.46, 1.8 }, { 1.3, -0.16, 1.2 } } do
			local lx, ly, s = h[1], h[2], h[3]
			local F = W * CFrame.new(sx * lx, ly, 0) * ANG(0, 0, math.atan2(-sx * lx, ly))
			heart(api, R, F, s + 0.22, 0.08, "gold")
			heart(api, R, F, s, 0.2, c)
			if i == 1 then
				heart(api, R, F, s * 0.5, 0.28, a)
				fball(api, R, F, 0.2, -s * 0.2, s * 0.17, 0.12, "white")
				-- the beat: a bigger pink heart on frames 1 and 3, in the torso otherwise
				local beat = api.count()
				heart(api, R, F, s * 0.68, 0.3, a)
				local hide = CFrame.new(HIDE_ROOT - F.Position)
				api.anim(beat, { CFrame.identity, hide, CFrame.identity, hide, hide, hide, hide, hide })
			else
				fball(api, R, F, 0.36, 0, 0.02, 0, a)
			end
		end
		api.anim(from, flapF(W, sx, 8, 0.15, 0.08))
		-- a little heart floating up off the wing
		local path: { Vector3 } = { HIDE_ROOT, HIDE_ROOT }
		for f = 1, 6 do
			table.insert(path, Vector3.new(sx * (1.6 + 0.06 * f) + 0.08 * sin(f * 1.3), 3.6 + 0.26 * f, -0.75))
		end
		local k = if sx > 0 then 2 else 5
		local f0 = api.count()
		local p0 = path[k % #path + 1]
		heart(api, R, CFrame.new(p0) * FACE_CAM, 0.4, 0.08, if sx > 0 then "r_mythic" else a)
		api.anim(f0, alongF(path, k))
	end
end

-- Sugar Rush Cup: a comet circling the wearer: a glowing star-bright head trailing a rainbow ribbon of six bands round
-- a tilted orbit, tapering behind it, glints in the trail. The whole of it goes round once every twelve frames, so the
-- comet passes in front, round the side and behind, and the glints twinkle in turn.
BACK.rainbow_comet_trail = function(api, c, a, _ctx)
	local R = api.ROOT
	local O = CFrame.new(0, 2.75, -0.1) * ANG(0.24, 0, 0.14)
	local r = 1.72
	local from = api.count()
	local BANDS = { "r_mythic", "r_legend", "yellow", "r_uncommon", "r_rare", c }
	-- the trail: five steps back from the head (at angle 0), each a ring piece per band, narrowing
	local steps = 5
	local span = 0.46 -- radians a step
	for k = 1, steps do
		local ang = -(k - 0.5) * span
		local wd = 0.18 * (1 - (k - 1) / (steps + 2))
		local len = 2 * r * math.tan(span / 2) + 0.06
		for b, col in BANDS do
			local y = (b - 3.5) * wd
			fput(api, R, O, len, wd + 0.01, 0.1, cos(ang) * r, y, sin(ang) * r, col, ANG(0, PI / 2 - ang, 0))
		end
	end
	-- the head: an amber glow round a glowing star-yellow ball and a white-hot core, a cross of light
	local hp = O * CFrame.new(r * cos(0.12), 0, r * sin(0.12))
	fball(api, R, hp, 0.8, 0, 0, 0, "r_legend")
	fball(api, R, hp, 0.58, 0.05, 0.03, 0.05, a)
	api.glow()
	fball(api, R, hp, 0.36, 0.14, 0.07, 0.12, "white")
	api.glow()
	-- glints in the trail, twinkling in turn (out of sight on the orbit's axis, inside the torso)
	local hideC = (O * CFrame.new(0, -0.95, 0)).Position
	for i, pat in { "12000000", "00120000", "00001200" } do
		local ang = -(i * 1.2) * span
		local gp = O * CFrame.new(cos(ang) * (r + 0.12), 0.32 * (if i == 2 then -1 else 1), sin(ang) * (r + 0.12))
		local S = CFrame.new(gp.Position) * FACE_CAM
		local g0 = api.count()
		sparkle(api, R, S, 0.36, "white")
		api.anim(g0, twinkleF(S, hideC, pat .. pat .. pat))
	end
	api.anim(from, spinF(O, 12, -2 * PI))
end

------------------------------------------------------------------ the Weekly Cup's hand pieces

-- the right hand's frame for the Weekly Cup's wands: held up and out to the side, so their tops stand beside the head
-- where the world's camera sees them; y along the shaft
local GRIP_OUT = CFrame.new(1.05, 1.25, 0.1) * ANG(-0.12, 0, -0.42)
-- a flat thing facing the world's camera squarely (turned toward it and tipped back to its 30 degree look down)
local CAM_SQ = ANG(0, PI / 4, 0) * ANG(-0.5, 0, 0)

-- the point s along a wand's shaft, as a frame facing the camera squarely
local function onShaft(s: number): CFrame
	return CFrame.new((GRIP_OUT * CFrame.new(0, s, 0)).Position) * CAM_SQ
end

-- Cloud Cup: a wand of a candy-striped stick with three marshmallows on it (white, pink, sky blue), a cloud floating
-- over its top (pink underneath) with a glowing pink star in front. The cloud bobs, two little marshmallows go round
-- it, glints twinkle.
HAND.marshmallow_wand = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fcyl(api, A, G, 0.16, 1.6, 0.44, c)
	for _, s in { -0.12, 0.18, 0.48, 0.78, 1.08 } do
		fcyl(api, A, G, 0.18, 0.08, s, a)
	end
	fball(api, A, G, 0.22, 0, -0.38, 0, a)
	fcyl(api, A, G, 0.46, 0.3, 1.4, "plate_white")
	fcyl(api, A, G, 0.46, 0.3, 1.72, a)
	fcyl(api, A, G, 0.46, 0.3, 2.04, "sky_day")
	local up = G.UpVector
	local T = onShaft(2.72)
	local from = api.count()
	fball(api, A, T, 0.9, 0, 0, 0, c)
	fball(api, A, T, 0.64, -0.5, -0.1, -0.04, c)
	fball(api, A, T, 0.64, 0.5, -0.06, 0, "plate_white")
	fball(api, A, T, 0.6, 0.14, 0.4, -0.1, c)
	fball(api, A, T, 0.46, -0.34, 0.3, -0.12, "plate_white")
	fball(api, A, T, 0.38, -0.26, -0.38, 0.06, a)
	fball(api, A, T, 0.38, 0.28, -0.36, 0.06, a)
	star(api, A, T * CFrame.new(0, -0.02, 0.5), 0.22, 0.1, a, "white", true)
	api.anim(from, moveF(8, function(f)
		return up * BOB8[f]
	end))
	-- two mini marshmallows going round the cloud
	local O = CFrame.new(T.Position)
	from = api.count()
	fput(api, A, O, 0.24, 0.26, 0.26, 0.66, 0.1, 0, "plate_white", nil, "Cylinder")
	fput(api, A, O, 0.24, 0.26, 0.26, -0.66, -0.1, 0, a, nil, "Cylinder")
	api.anim(from, spinF(O, 8, PI))
	local g1 = (T * CFrame.new(-0.7, 0.56, 0.1)).Position
	local g2 = (T * CFrame.new(0.62, 0.5, 0.1)).Position
	glint(api, A, g1.X, g1.Y, g1.Z, 0.34, HIDE_ARM, "12100000")
	glint(api, A, g2.X, g2.Y, g2.Z, 0.28, HIDE_ARM, "00001210")
end

-- Taffy Cup: a big pop of pulled taffy on a white stick: a cream disc rimmed in pink with a swirl of pink and caramel
-- and a shine, a pink ribbon bow under it. The swirl twirls (half a turn a loop: its two arms take turns), a caramel
-- drop runs off its bottom and glints twinkle.
HAND.taffy_twirl_pop = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fcyl(api, A, G, 0.14, 2.0, 0.6, "cream")
	local B = onShaft(1.42)
	fput(api, A, B, 0.34, 0.34, 0.12, -0.21, 0, 0, c, DIAMOND)
	fput(api, A, B, 0.34, 0.34, 0.12, 0.21, 0, 0, c, DIAMOND)
	fput(api, A, B, 0.1, 0.32, 0.1, -0.1, -0.24, 0, c, ANG(0, 0, -0.3))
	fput(api, A, B, 0.1, 0.32, 0.1, 0.1, -0.24, 0, c, ANG(0, 0, 0.3))
	fball(api, A, B, 0.18, 0, 0, 0.04, c)
	local P = onShaft(2.3)
	fdisc(api, A, P, 1.6, 0.16, 0, 0, -0.03, c)
	fdisc(api, A, P, 1.38, 0.22, 0, 0, 0, "cream")
	local from = api.count()
	for arm = 0, 1 do
		for i = 1, 7 do
			local rr = 0.06 + 0.088 * i
			local ang = arm * PI + i * 0.72
			fput(api, A, P, 0.22, 0.18, 0.06, cos(ang) * rr, sin(ang) * rr, 0.12, if i % 2 == 0 then a else c, ANG(0, 0, ang + PI / 2))
		end
	end
	fball(api, A, P, 0.18, 0, 0, 0.1, "white")
	api.anim(from, rollF(P, 8, -PI))
	fput(api, A, P, 0.22, 0.1, 0.06, -0.36, 0.4, 0.16, "white", ANG(0, 0, 0.7))
	-- the caramel run off the bottom, and its drop
	fput(api, A, P, 0.14, 0.24, 0.08, 0.24, -0.78, 0.06, a)
	local function at(dy: number): Vector3
		return (P * CFrame.new(0.24, -0.92 - dy, 0.08)).Position
	end
	local path = { at(0), at(0.08), at(0.22), at(0.44), at(0.72), HIDE_ARM, HIDE_ARM, at(-0.08) }
	from = api.count()
	local p0 = path[1]
	api.ball(A, 0.18, p0.X, p0.Y, p0.Z, a)
	api.anim(from, alongF(path, 0))
	local g1 = (P * CFrame.new(-0.72, 0.6, 0.12)).Position
	local g2 = (P * CFrame.new(0.76, 0.36, 0.12)).Position
	glint(api, A, g1.X, g1.Y, g1.Z, 0.32, HIDE_ARM, "21000000")
	glint(api, A, g2.X, g2.Y, g2.Z, 0.28, HIDE_ARM, "00002100")
end

-- Crunch Cup: a royal scepter: a wafer shaft with baked lines, a gold pommel and collars, a flower-shaped shortbread
-- in a gold mount (docker holes, an amber gem in its middle) and an amber crystal floating over it. The crystal turns,
-- three crumbs of brittle circle it and the gem glints.
HAND.biscuit_scepter = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fcyl(api, A, G, 0.2, 1.75, 0.5, c)
	for _, s in { -0.1, 0.3, 0.7, 1.1 } do
		fcyl(api, A, G, 0.22, 0.06, s, "wood")
	end
	fball(api, A, G, 0.3, 0, -0.44, 0, a)
	fcyl(api, A, G, 0.3, 0.12, 0.08, a)
	fcyl(api, A, G, 0.32, 0.14, 1.4, a)
	fcyl(api, A, G, 0.58, 0.12, 1.54, a)
	local B = onShaft(2.08)
	fdisc(api, A, B, 1.0, 0.16, 0, 0, 0, "floor_b")
	for k = 0, 7 do
		local ang = k * PI / 4
		fdisc(api, A, B, 0.32, 0.14, cos(ang) * 0.48, sin(ang) * 0.48, -0.01, "floor_b")
	end
	fdisc(api, A, B, 0.7, 0.04, 0, 0, 0.09, "sponge")
	for _, d in { { -0.2, 0.17 }, { 0.2, 0.17 }, { -0.2, -0.19 }, { 0.2, -0.19 } } do
		fput(api, A, B, 0.08, 0.08, 0.06, d[1], d[2], 0.12, "wood")
	end
	fdisc(api, A, B, 0.34, 0.06, 0, 0, 0.12, a)
	fdisc(api, A, B, 0.24, 0.08, 0, 0, 0.14, "r_legend")
	api.glow()
	-- prongs of the mount holding it
	for _, sx in { -1, 1 } do
		fput(api, A, B, 0.09, 0.36, 0.1, sx * 0.34, -0.44, 0.04, a, ANG(0, 0, sx * 0.5))
	end
	-- the crystal: two points (up and down) of amber, a streak of light, turning
	local Cr = CFrame.new((G * CFrame.new(0, 3.12, 0)).Position)
	local from = api.count()
	local Cf = Cr * FACE_CAM
	spike(api, A, Cf, 0.46, 0.56, 0.16, 0, 0.28, 0, "r_legend")
	api.glow()
	spike(api, A, Cf * ANG(0, 0, PI), 0.46, 0.34, 0.16, 0, 0.17, 0, "oven_glow")
	fput(api, A, Cf, 0.07, 0.3, 0.18, -0.06, 0.2, 0, "yellow")
	api.anim(from, spinF(Cr, 8, PI))
	-- crumbs circling it
	from = api.count()
	for k = 0, 2 do
		local ang = k * 2 * PI / 3
		fput(api, A, Cr, 0.15, 0.15, 0.15, cos(ang) * 0.46, -0.04, sin(ang) * 0.46, if k == 1 then "r_legend" else "floor_b", ANG(0.5, ang, 0.5))
	end
	api.anim(from, spinF(Cr * ANG(0.25, 0, 0), 8, -2 * PI / 3))
	local g = (B * CFrame.new(0.06, 0.07, 0.2)).Position
	glint(api, A, g.X, g.Y, g.Z, 0.32, HIDE_ARM, "12000001")
end

-- Zen Tea Cup: a bamboo wand (pale nodes, leaves) with a tea whisk at its top: a cream collar with a jade band and a
-- bulb of cream and straw tines round a cream core, a dab of matcha on top. The whisk spins, three jade motes go round
-- it and a jade charm swings on a red cord.
HAND.bamboo_whisk_wand = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fcyl(api, A, G, 0.2, 1.85, 0.5, c)
	for _, s in { -0.24, 0.26, 0.76, 1.26 } do
		fcyl(api, A, G, 0.24, 0.08, s, "sponge")
	end
	local Lf = onShaft(0.76)
	fput(api, A, Lf, 0.14, 0.56, 0.06, -0.24, 0.16, 0, "grass", ANG(0, 0, 0.9))
	fput(api, A, Lf, 0.12, 0.46, 0.06, 0.22, 0.2, 0, c, ANG(0, 0, -0.8))
	fput(api, A, onShaft(0.26), 0.12, 0.46, 0.06, 0.22, 0.14, 0, "grass", ANG(0, 0, -0.9))
	fcyl(api, A, G, 0.36, 0.32, 1.58, a)
	fcyl(api, A, G, 0.38, 0.08, 1.5, "r_uncommon")
	-- the whisk's bulb, spinning about the shaft
	local Wk = G * CFrame.new(0, 2.14, 0)
	local from = api.count()
	fball(api, A, Wk, 0.62, 0, 0.02, 0, a)
	for k = 0, 11 do
		local ang = k * PI / 6
		fput(api, A, Wk, 0.11, 0.96, 0.11, cos(ang) * 0.32, 0.06, sin(ang) * 0.32, if k % 2 == 0 then "cream" else "sponge", ANG(sin(ang) * 0.24, 0, -cos(ang) * 0.24))
	end
	fball(api, A, Wk, 0.46, 0, 0.42, 0, a)
	fball(api, A, Wk, 0.28, 0.04, 0.6, 0.04, "green")
	api.anim(from, spinF(Wk, 8, PI / 3))
	-- jade motes going round it
	from = api.count()
	for k = 0, 2 do
		local ang = k * 2 * PI / 3
		fball(api, A, Wk, 0.24, cos(ang) * 0.8, 0.12 * sin(ang * 2), sin(ang) * 0.8, c)
		api.glow()
	end
	api.anim(from, spinF(Wk * ANG(0.3, 0, 0.15), 8, 2 * PI / 3))
	-- the jade charm on a cord from the collar, swinging
	local top = (G * CFrame.new(0.16, 1.5, 0.08)).Position
	from = api.count()
	link(api, A, top.X, top.Y, top.Z, top.X + 0.22, top.Y - 0.44, top.Z + 0.14, 0.06, "berry_red")
	local J = CFrame.new(top.X + 0.24, top.Y - 0.6, top.Z + 0.15) * CAM_SQ
	fdisc(api, A, J, 0.34, 0.08, 0, 0, 0, "gold")
	fdisc(api, A, J, 0.26, 0.1, 0, 0, 0, c)
	fdisc(api, A, J, 0.1, 0.12, 0, 0, 0, "gold")
	api.anim(from, turnF(CFrame.new(top) * CAM_SQ, 8, function(f)
		return 0, 0, osc(f, 8, 0.35)
	end))
end

-- Sweetheart Cup: a whisk with heart-shaped loops (one facing the camera, one across) on a gold handle with pink
-- grips, little white wings on its collar and a glowing heart in its cage. The heart beats, the wings flap, the cage
-- rocks to and fro and hearts float up off it.
HAND.cupid_whisk = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fcyl(api, A, G, 0.22, 1.12, 0.26, "gold")
	for _, s in { -0.1, 0.22, 0.54 } do
		fcyl(api, A, G, 0.25, 0.1, s, a)
	end
	heart(api, A, onShaft(-0.42), 0.32, 0.12, c)
	fcyl(api, A, G, 0.32, 0.14, 0.88, "plate_gold")
	-- little wings on the collar, flapping
	for _, sx in { -1, 1 } do
		local Wg = onShaft(0.9) * CFrame.new(sx * 0.14, 0, -0.06)
		local from = api.count()
		fput(api, A, Wg, 0.48, 0.2, 0.06, sx * 0.28, 0.1, 0, "white", ANG(0, 0, sx * 0.45))
		fput(api, A, Wg, 0.38, 0.17, 0.06, sx * 0.25, -0.06, 0, "white", ANG(0, 0, sx * 0.1))
		fput(api, A, Wg, 0.26, 0.14, 0.06, sx * 0.2, -0.2, 0, "white", ANG(0, 0, -sx * 0.25))
		api.anim(from, turnF(Wg, 8, function(f)
			return 0, sx * osc(f, 8, 0.4), sx * osc(f, 8, 0.25, -0.6)
		end))
	end
	-- the cage: two heart loops of wire, rocking
	local Cg = G * CFrame.new(0, 0.94, 0)
	local cage = api.count()
	local HL = { { 0, 0 }, { 0.5, 0.48 }, { 0.54, 1.0 }, { 0.26, 1.24 }, { 0, 1.02 } }
	for li, F in { G * ANG(0, PI / 4, 0), G * ANG(0, -PI / 4, 0) } do
		local L = CFrame.new(Cg.Position) * F.Rotation
		for _, sx in { -1, 1 } do
			for k = 1, #HL - 1 do
				local p, q = HL[k], HL[k + 1]
				strip(api, A, L, sx * p[1], p[2], sx * q[1], q[2], 0.13, 0.12, if li == 1 then c else a)
			end
		end
	end
	api.anim(cage, turnF(Cg, 8, function(f)
		return 0, osc(f, 8, 0.32), 0
	end))
	-- the glowing heart inside, beating (on the axis the cage rocks about)
	local Hc = onShaft(1.56)
	heart(api, A, Hc, 0.38, 0.14, "r_mythic")
	api.glow()
	local beat = api.count()
	heart(api, A, Hc * CFrame.new(0, 0.01, 0.03), 0.52, 0.14, "r_mythic")
	api.glow()
	local hide = CFrame.new(HIDE_ARM - Hc.Position)
	api.anim(beat, { CFrame.identity, hide, CFrame.identity, hide, hide, hide, hide, hide })
	-- hearts floating up off it
	for i = 0, 1 do
		local path: { Vector3 } = { HIDE_ARM, HIDE_ARM }
		local base = (G * CFrame.new(0, 2.25, 0)).Position
		for f = 1, 6 do
			table.insert(path, base + Vector3.new((i - 0.5) * 0.14 * f + 0.08 * sin(f * 1.5), 0.2 * f, 0.03 * f))
		end
		local k = if i == 0 then 2 else 5
		local from = api.count()
		local p0 = path[k % #path + 1]
		heart(api, A, CFrame.new(p0) * CAM_SQ, 0.3, 0.08, if i == 0 then a else "r_mythic")
		api.anim(from, alongF(path, k))
	end
end

-- Sugar Rush Cup: a rocket pop on its stick: rainbow bands narrowing to a white nose with a yellow tip, white
-- sprinkles, a porthole, three fins, and a flame under it as if it were taking off. It hovers up and down off the
-- stick on its flickering flame, four sprinkles whirl round its nose and a star twinkles over it.
HAND.rocket_pop_wand = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fput(api, A, G, 0.26, 1.3, 0.1, 0, 0.3, 0, "floor_a")
	local up = G.UpVector
	local from = api.count()
	local bands = { "berry_red", "r_legend", "yellow", "r_uncommon", "r_rare", c }
	for i, col in bands do
		fcyl(api, A, G, 0.78 - i * 0.04, 0.24, 1.1 + (i - 1) * 0.23, col)
	end
	fball(api, A, G, 0.56, 0, 2.42, 0, "white")
	fball(api, A, G, 0.28, 0, 2.7, 0, a)
	-- a porthole and sprinkles on the side the camera sees
	local Fc = G * ANG(0, PI / 4, 0)
	fdisc(api, A, Fc, 0.34, 0.08, 0, 1.9, 0.33, "white")
	fdisc(api, A, Fc, 0.22, 0.1, 0, 1.9, 0.34, "sky_day")
	for _, d in { { -0.2, 1.18, 0.6 }, { 0.18, 1.4, -0.5 }, { -0.16, 1.62, 0.4 }, { 0.16, 2.12, -0.7 }, { -0.12, 2.22, 0.3 } } do
		fput(api, A, Fc, 0.16, 0.06, 0.06, d[1], d[2], 0.36, "white", ANG(0, 0, d[3]))
	end
	-- three fins
	for k = 0, 2 do
		local Fk = G * ANG(0, k * 2 * PI / 3 + PI / 4, 0)
		tri(api, A, Fk, 0.34, 0.56, 0.07, 0.52, 1.04, 0, c, true)
	end
	-- the flame: neon tongues under it, flickering
	-- { width, height, across, colour }
	local flame: { { any } } = { { 0.34, 0.26, 0, "yellow" }, { 0.22, 0.38, 0.14, "oven_glow" }, { 0.16, 0.28, -0.12, "white" } }
	for j, fl in flame do
		local fw, fh, fx = fl[1] :: number, fl[2] :: number, fl[3] :: number
		local f0 = api.count()
		fput(api, A, Fc, fw, fh, fw, fx, 0.98 - fh / 2, 0.05 * j, fl[4] :: string)
		api.glow()
		local P = Fc * CFrame.new(fx, 1.0, 0)
		api.anim(f0, turnF(P, 4, function(f)
			return 0, 0, osc(f, 4, 0.22, j * 1.3)
		end))
	end
	-- sprinkles whirling round the nose (two colours twice over: half a turn a loop)
	local O = G * CFrame.new(0, 2.3, 0)
	local f1 = api.count()
	for k = 0, 3 do
		local ang = k * PI / 2
		fput(api, A, O, 0.28, 0.09, 0.09, cos(ang) * 0.58, 0, sin(ang) * 0.58, if k % 2 == 0 then "r_mythic" else "r_uncommon", ANG(0, PI / 2 - ang, 0.5))
	end
	api.anim(f1, spinF(O, 8, PI))
	local g = (G * CFrame.new(0.08, 3.08, 0.1)).Position
	glint(api, A, g.X, g.Y, g.Z, 0.4, HIDE_ARM, "12210000", "yellow")
	-- the whole rocket hovers on its flame
	api.anim(from, moveF(8, function(f)
		return up * BOB8[f]
	end))
end

------------------------------------------------------------------ the reward looks

-- The rewards' looks (Data/Cosmetics `reward`: never sold, unlocked only as that prize): the Lucky Spin's four, very
-- rare, in gold and luck (clovers, horseshoes, shooting stars); the daily streak's breakfast collection; the streak's
-- milestones. They move like the Weekly Cup's (Api.anim on the world's clock); still pictures show the rest pose.
-- Their shared shapes and moves are in REWARD (one local: this chunk keeps its locals few), which the shop's
-- animated pieces below use too.
local REWARD = {}

-- a four-leaf clover facing F's Z: four round leaves s across, turned corner out, notched apart round its heart
-- (about 1.8 s across)
function REWARD.clover(api: Api, bone: number, F: CFrame, s: number, t: number, color: string)
	for k = 0, 3 do
		local ang = PI / 4 + k * PI / 2
		fdisc(api, bone, F, s, t, cos(ang) * s * 0.58, sin(ang) * s * 0.58, 0, color)
	end
end

-- a tongue of flame up F's Y (spike's shape: w across the base, h tall, the right half h2), centred dy up, all aglow
function REWARD.flame(api: Api, bone: number, F: CFrame, w: number, h: number, t: number, dy: number, color: string, h2: number?)
	tri(api, bone, F, w / 2, h, t, -w / 4, dy, 0, color)
	api.glow()
	local hr = h2 or h
	tri(api, bone, F, w / 2, hr, t, w / 4, dy - (h - hr) / 2, 0, color, true)
	api.glow()
end

-- a four-pointed star facing S's Z: a cross of glowing bars `len` long round a glowing diamond in `core`
function REWARD.twinkle(api: Api, bone: number, S: CFrame, len: number, color: string, core: string)
	fput(api, bone, S, len, len * 0.24, 0.1, 0, 0, 0, color)
	api.glow()
	fput(api, bone, S, len * 0.24, len, 0.1, 0, 0, 0, color)
	api.glow()
	fput(api, bone, S, len * 0.32, len * 0.32, 0.13, 0, 0, 0, core, DIAMOND)
	api.glow()
end

-- n frames carrying a part round a loop by moving it only, so it keeps its face to the camera: at(ang) is the loop's
-- point at angle ang, the part rests at at(a0) and goes `turn` radians round a loop
function REWARD.orbitF(n: number, a0: number, turn: number, at: (number) -> Vector3): { CFrame }
	local rest = at(a0)
	return moveF(n, function(f)
		return at(a0 + turn * (f - 1) / n) - rest
	end)
end

-- Lucky Spin, very rare: a gold crown trimmed in yellow whose six points (three in front, one a side, one behind) end
-- in four-leaf clovers, the front one biggest; an emerald set in gold at the front between two pearls, green gems on
-- its sides. The clovers sway on their points, each on its own beat; three sparkles circle the crown; the emerald
-- glints.
HAT.four_leaf_crown = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local z0 = -0.05
	api.add(H, 1.84, 0.44, 1.84, 0, t + 0.2, z0, c)
	api.add(H, 1.9, 0.08, 1.9, 0, t + 0.4, z0, "yellow")
	api.add(H, 1.9, 0.08, 1.9, 0, t + 0.01, z0, "plate_gold")
	disc(api, H, 0.5, 0.08, 0, t + 0.2, z0 + 0.95, "plate_gold")
	api.add(H, 0.32, 0.32, 0.1, 0, t + 0.2, z0 + 0.99, a, DIAMOND)
	api.glow()
	for _, sx in { -1, 1 } do
		api.ball(H, 0.14, sx * 0.42, t + 0.2, z0 + 0.94, "white")
		api.add(H, 0.1, 0.22, 0.22, sx * 0.95, t + 0.2, z0, a, ANG(PI / 4, 0, 0))
	end
	-- the points: { x, z, facing, height, leaf }
	local pts = {
		{ 0, 0.88, 0, 0.6, 0.36 },
		{ -0.62, 0.88, 0, 0.36, 0.28 },
		{ 0.62, 0.88, 0, 0.36, 0.28 },
		{ 0.88, 0, PI / 2, 0.46, 0.3 },
		{ -0.88, 0, -PI / 2, 0.46, 0.3 },
		{ 0, -0.88, PI, 0.42, 0.3 },
	}
	for i, p in pts do
		local h, s = p[4], p[5]
		local F = CFrame.new(p[1], t + 0.42, z0 + p[2]) * ANG(0, p[3], 0)
		spike(api, H, F, 0.46, h, 0.12, 0, h / 2, 0, c)
		local T = F * CFrame.new(0, h, 0.02)
		local from = api.count()
		REWARD.clover(api, H, T * ANG(-0.2, 0, 0) * CFrame.new(0, s * 0.42, 0.03), s, 0.09, "grass")
		api.anim(from, turnF(T, 8, function(f)
			return 0, 0, osc(f, 8, 0.2, i * 1.3)
		end))
	end
	-- three sparkles circling on a tilted ring (a third of a turn a loop), faces to the camera
	local O = CFrame.new(0, t + 0.62, z0) * ANG(0.22, 0, 0.12)
	local function at(ang: number): Vector3
		return (O * CFrame.new(cos(ang) * 1.3, 0, sin(ang) * 1.3)).Position
	end
	for k = 0, 2 do
		local a0 = k * 2 * PI / 3 + 0.5
		local from = api.count()
		sparkle(api, H, CFrame.new(at(a0)) * FACE_CAM, 0.36, "white")
		api.anim(from, REWARD.orbitF(8, a0, 2 * PI / 3, at))
	end
	glint(api, H, 0.12, t + 0.32, z0 + 1.1, 0.34, HIDE_HEAD, "00012100")
end

-- Daily (breakfast): a golden croissant curled round into a crown, worn tipped forward a little: its fat middle roll
-- high over the brow, the rolls narrowing round the sides to its two horns, which cross and turn up at the back; darker baked
-- creases between the rolls, a shine along the front ones and a few flakes; a pat of butter sits on the front roll as
-- its jewel, melting a little. Warm from the oven: two wisps of steam curl up off it, and the butter glints.
HAT.croissant_crown = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local z0, R = -0.05, 0.9
	local y = t + 0.3
	local F = CFrame.new(0, y, z0) * ANG(-0.26, 0, 0)
	local step = 2 * PI / 10
	local len = 2 * R * math.tan(step / 2)
	for j = -4, 4 do
		local aj = math.abs(j)
		local ang = PI / 2 + j * step
		local d = 0.86 - 0.115 * aj
		fput(api, H, F, len * 0.8, d, d, cos(ang) * R, 0, sin(ang) * R, c, ANG(0, PI / 2 - ang, 0), "Cylinder")
		if j < 4 then
			local ang2 = ang + step / 2
			local d2 = (0.86 - 0.115 * math.abs(j + 0.5)) * 0.74
			fput(api, H, F, len * 0.32, d2, d2, cos(ang2) * R, 0, sin(ang2) * R, "chocolate", ANG(0, PI / 2 - ang2, 0), "Cylinder")
		end
		if aj <= 1 then
			-- the shine on the front rolls' tops (toward the camera)
			local ra = R + 0.1
			fput(api, H, F, len * 0.5, 0.05, 0.16, cos(ang) * ra, d / 2 - 0.04, sin(ang) * ra, "sponge", ANG(0, PI / 2 - ang, 0) * ANG(0.4, 0, 0))
		end
	end
	-- the horns: from the last rolls up and over each other at the back, browner at their tips
	for _, sx in { -1, 1 } do
		local b = 3 * PI / 2 - sx * 0.44
		local e = 3 * PI / 2 + sx * 0.16
		local p1 = F * CFrame.new(cos(b) * R, 0.02, sin(b) * R)
		local p2 = F * CFrame.new(cos(e) * (R - 0.04), 0.4, sin(e) * (R - 0.04))
		link(api, H, p1.X, p1.Y, p1.Z, p2.X, p2.Y, p2.Z, 0.26, c)
		api.ball(H, 0.24, p2.X, p2.Y + 0.04, p2.Z, "wood")
	end
	-- flakes on the front rolls
	local f1, f2 = F * CFrame.new(-0.5, 0.33, 0.72), F * CFrame.new(0.6, 0.27, 0.6)
	api.add(H, 0.13, 0.05, 0.1, f1.X, f1.Y, f1.Z, "sponge", ANG(0.3, 0.6, 0.2))
	api.add(H, 0.1, 0.05, 0.13, f2.X, f2.Y, f2.Z, "sponge", ANG(-0.2, 0.3, 0.4))
	-- the butter: a pat on the front roll, a lighter top, a drop melting down the front
	local bp = F * CFrame.new(0, 0.46, R + 0.04)
	local by, bz = bp.Y, bp.Z
	api.add(H, 0.5, 0.16, 0.4, 0.04, by, bz, a, ANG(0, 0.25, 0.08))
	api.add(H, 0.4, 0.03, 0.3, 0.03, by + 0.09, bz, "cream", ANG(0, 0.25, 0.08))
	api.add(H, 0.11, 0.26, 0.08, 0.18, by - 0.19, bz + 0.35, a)
	api.ball(H, 0.15, 0.18, by - 0.33, bz + 0.36, a)
	-- steam: two wisps of two puffs rising in a curl, gone into the head between
	local wisps = { { -0.46, 0.5, 0 }, { 0.5, 0.38, 2.4 } }
	for wsp, wd in wisps do
		local x0, z1, ph = wd[1], z0 + wd[2], wd[3]
		local path: { Vector3 } = { HIDE_HEAD }
		for f = 1, 7 do
			path[f + 1] = Vector3.new(x0 + 0.16 * sin(f * 0.9 + ph), y + 0.52 + 0.17 * f, z1 + 0.1 * cos(f * 0.9 + ph))
		end
		for i, k in { wsp, wsp + 3 } do
			local from = api.count()
			local p0 = path[k % 8 + 1]
			api.ball(H, 0.38 - i * 0.07, p0.X, p0.Y, p0.Z, if i == 1 then "white" else "plate_white")
			api.anim(from, alongF(path, k))
		end
	end
	glint(api, H, 0.2, by + 0.14, bz + 0.18, 0.3, HIDE_HEAD, "0001210000000000")
end

-- Daily (breakfast): sunglasses whose lenses are a sunrise: a pink sky over orange and gold, a glowing sun rising off
-- each lens's bottom rim, in white frames with arms back to the ears. Now and then a bar of light sweeps across one
-- lens, then the other, and a glint twinkles at its corner.
FACE.sunrise_shades = function(api, c, a, _ctx)
	local H = api.HEAD
	local y = 3.37
	for _, sx in { -1, 1 } do
		local x = sx * 0.47
		api.add(H, 0.8, 0.6, 0.06, x, y, 1.16, "white")
		api.add(H, 0.68, 0.18, 0.04, x, y + 0.14, 1.2, a)
		api.add(H, 0.68, 0.15, 0.04, x, y - 0.025, 1.2, c)
		api.add(H, 0.68, 0.14, 0.04, x, y - 0.165, 1.2, "r_legend")
		disc(api, H, 0.28, 0.04, x, y - 0.2, 1.22, "yellow")
		api.glow()
		api.add(H, 0.8, 0.13, 0.06, x, y - 0.275, 1.24, "white")
		api.add(H, 0.1, 0.12, 0.92, sx * 1.06, y + 0.12, 0.6, "white")
	end
	api.add(H, 0.22, 0.1, 0.06, 0, y + 0.12, 1.18, "white")
	-- the sweeps (a loop of 14 frames: the right lens's on frames 1-3, the left's on 8-10), each with its glint
	for i, sx in { 1, -1 } do
		local x = sx * 0.47
		local function at(dx: number): Vector3
			return Vector3.new(x + dx, y + 0.02, 1.235)
		end
		local hide = Vector3.new(x, y, 0.6)
		local path: { Vector3 } = { at(-0.2), at(0), at(0.2) }
		for _ = 4, 14 do
			table.insert(path, hide)
		end
		local k = if i == 1 then 0 else 7
		local from = api.count()
		local p0 = path[k % 14 + 1]
		api.add(H, 0.07, 0.38, 0.03, p0.X, p0.Y, p0.Z, "white", ANG(0, 0, -0.7))
		api.glow()
		api.anim(from, alongF(path, k))
		glint(api, H, x + 0.3, y + 0.24, 1.28, 0.26, HIDE_HEAD, if i == 1 then "00120000000000" else "00000000012000")
	end
end

-- Lucky Spin, very rare: wings of shooting stars: three a side flying out from the spine, each a glowing star at the
-- head of a golden tail that narrows to the spine with a bright streak down it: a big five-pointed star high over
-- the shoulder, two four-pointed ones below it. They flap; the big stars turn, the small ones twinkle, a glint flashes
-- and a speck of stardust falls off each wing.
REWARD.SHOOTING = {
	-- { out, up (the star's place in the wing), its size, its points }
	{ 1.5, 2.6, 0.34, 5 },
	{ 2.0, 1.45, 0.8, 4 },
	{ 1.8, 0.3, 0.66, 4 },
} :: { { number } }
BACK.shooting_star_wings = function(api, c, a, _ctx)
	local R = api.ROOT
	for _, sx in { -1, 1 } do
		local W = bigWing(sx)
		local from = api.count()
		for i, s in REWARD.SHOOTING do
			local lx, ly, size = s[1], s[2], s[3]
			local dx, dy = lx - 0.12, ly - 0.02
			local L = math.sqrt(dx * dx + dy * dy)
			-- the tail, wide at the star and narrowing to a point at the spine (a spike turned end over end)
			local T = W * CFrame.new(sx * 0.12, 0.02, 0) * ANG(0, 0, -sx * math.atan2(dx, dy)) * CFrame.new(0, L / 2, 0) * ANG(0, 0, PI)
			spike(api, R, T, if i == 1 then 0.56 else 0.46, L, 0.1, 0, 0, 0, c)
			fput(api, R, T, 0.12, L * 0.7, 0.14, 0, -L * 0.12, 0, a)
			api.glow()
			local S = W * CFrame.new(sx * lx, ly, 0)
			local s0 = api.count()
			if s[4] == 5 then
				star(api, R, S, size, 0.14, a, "white", true)
				api.anim(s0, rollF(S, 8, -sx * 2 * PI / 5))
			else
				REWARD.twinkle(api, R, S, size, a, "white")
				api.anim(s0, twinkleF(S, HIDE_ROOT, if i == 2 then "11211121" else "21112111"))
			end
		end
		local g = (W * CFrame.new(sx * 1.05, 2.95, 0.2)).Position
		glint(api, R, g.X, g.Y, g.Z, 0.34, HIDE_ROOT, if sx > 0 then "00002100" else "21000000")
		api.anim(from, flapF(W, sx, 8, 0.16, 0.1))
		-- stardust falling off the big star, out of sight in the torso between
		local path: { Vector3 } = { HIDE_ROOT, HIDE_ROOT }
		for f = 1, 6 do
			table.insert(path, (W * CFrame.new(sx * (1.6 + 0.12 * f), 2.3 - 0.32 * f, 0.1)).Position)
		end
		local k = if sx > 0 then 3 else 6
		local d0 = api.count()
		local p0 = path[k % 8 + 1]
		api.add(R, 0.13, 0.13, 0.13, p0.X, p0.Y, p0.Z, a, ANG(PI / 4, PI / 4, 0))
		api.glow()
		api.anim(d0, alongF(path, k))
	end
end

-- Daily (breakfast): a backpack that is a jar of strawberry jam: red jam behind glass (a glassy base and shoulder,
-- shine down its side, strawberry pieces in it), a red gingham cloth over its lid tied with twine in a bow, a cream
-- label with a strawberry, red straps over the shoulders. A bee buzzes round it, the bow's tails flutter and the glass
-- glints.
BACK.jam_jar_backpack = function(api, c, a, _ctx)
	local R = api.ROOT
	local z0, y0 = -1.28, 1.68
	api.cyl(R, 1.46, 1.12, 0, y0, z0, c)
	api.cyl(R, 1.52, 0.12, 0, y0 - 0.59, z0, "window")
	api.cyl(R, 1.38, 0.16, 0, y0 + 0.64, z0, "window")
	-- strawberry pieces and the glass's shine, round the side the camera and the back see
	for _, d in { { 0.25, 0.22, 0.2 }, { -0.9, -0.28, 0.18 } } do
		api.ball(R, d[3] * 1.2, cos(d[1]) * 0.7, y0 + d[2], z0 + sin(d[1]) * 0.7, "plate_lacquer")
	end
	for _, ang in { -2.1, -0.2 } do
		api.add(R, 0.09, 0.84, 0.06, cos(ang) * 0.74, y0 + 0.05, z0 + sin(ang) * 0.74, "white", ANG(0, -PI / 2 - ang, 0))
	end
	-- the label facing back and to the camera's side, a strawberry on it
	local L = CFrame.new(0, y0 - 0.06, z0) * ANG(0, PI - 0.25, 0) * CFrame.new(0, 0, 0.73)
	fdisc(api, R, L, 0.72, 0.05, 0, 0, 0, "cream")
	fball(api, R, L, 0.34, 0, -0.05, 0.06, c)
	fput(api, R, L, 0.14, 0.11, 0.05, -0.06, 0.13, 0.12, "r_uncommon", ANG(0, 0, 0.5))
	fput(api, R, L, 0.14, 0.11, 0.05, 0.06, 0.13, 0.12, "r_uncommon", ANG(0, 0, -0.5))
	-- the cloth: red gingham (white checks on red) over the lid, its corners hanging down
	local top = y0 + 0.76
	api.add(R, 1.62, 0.08, 1.62, 0, top, z0, c)
	for _, d in { { 0.54, 0 }, { -0.54, 0 }, { 0, 0.54 }, { 0, -0.54 } } do
		api.add(R, 0.54, 0.09, 0.54, d[1], top + 0.005, z0 + d[2], a)
	end
	for k = 0, 3 do
		local ang = PI / 4 + k * PI / 2
		local F = CFrame.new(cos(ang) * 0.86, top - 0.22, z0 + sin(ang) * 0.86) * ANG(0, PI / 2 - ang, 0) * ANG(-0.25, 0, 0)
		fput(api, R, F, 0.4, 0.4, 0.06, 0, 0, 0, if k % 2 == 0 then c else a, DIAMOND)
	end
	api.cyl(R, 1.43, 0.08, 0, top - 0.13, z0, "cream")
	-- the bow on the camera's side, its tails fluttering
	local B = CFrame.new(0.73, top - 0.13, z0 + 0.05) * ANG(0, PI / 2, 0)
	fput(api, R, B, 0.24, 0.16, 0.06, -0.13, 0.03, 0, "cream", ANG(0, 0, 0.4))
	fput(api, R, B, 0.24, 0.16, 0.06, 0.13, 0.03, 0, "cream", ANG(0, 0, -0.4))
	local from = api.count()
	fput(api, R, B, 0.07, 0.26, 0.05, -0.07, -0.14, 0.02, "cream", ANG(0, 0, -0.3))
	fput(api, R, B, 0.07, 0.26, 0.05, 0.07, -0.14, 0.02, "cream", ANG(0, 0, 0.3))
	api.anim(from, turnF(B, 8, function(f)
		return 0, 0, osc(f, 8, 0.22)
	end))
	straps(api, c)
	-- the bee: a striped body, two wings beating, buzzing round the jar's top past the head
	local O = CFrame.new(0, 2.95, -1.78)
	local function at(ang: number): Vector3
		return (O * CFrame.new(cos(ang) * 1.6, 0.16 * sin(2 * ang), sin(ang) * 0.55)).Position
	end
	local a0 = 0.15
	local p0 = at(a0)
	local bee = api.count()
	api.ball(R, 0.32, p0.X, p0.Y, p0.Z, "yellow")
	api.add(R, 0.08, 0.33, 0.33, p0.X, p0.Y, p0.Z, "black", nil, "Cylinder")
	local wings = api.count()
	for _, sx in { -1, 1 } do
		api.add(R, 0.1, 0.05, 0.22, p0.X + sx * 0.07, p0.Y + 0.2, p0.Z, "white", ANG(0, 0, sx * 0.5))
	end
	api.anim(wings, turnF(CFrame.new(p0), 2, function(f)
		return 0, 0, if f == 1 then 0 else 0.5
	end))
	api.anim(bee, REWARD.orbitF(8, a0, 2 * PI, at))
	glint(api, R, 0.78, y0 + 0.24, z0 + 0.14, 0.34, HIDE_ROOT, "0012100000")
end

-- Streak (30 days): phoenix wings of fire: four long flame feathers a side fanning up past the head and out, each
-- narrow at the spine, widest a third of the way out and drawn to a ragged point: red at the rim, glowing orange
-- within, white-gold at the heart of the top two; a tongue of flame at the spine between them. The fire within
-- flickers on its own quick beat, the rims sway on a slower one, an ember rises off each wing, and they beat slowly.
REWARD.PHOENIX = {
	-- { angle out from straight up, length, width at its widest, the ragged half's share of the point, a white-gold core }
	{ 0.12, 3.65, 1.05, 0.8, 1 },
	{ 0.52, 3.5, 1.1, 0.84, 1 },
	{ 0.92, 2.8, 0.95, 0.76, 0 },
	{ 1.32, 2.1, 0.8, 0.82, 0 },
} :: { { number } }
BACK.phoenix_wings = function(api, c, a, _ctx)
	local R = api.ROOT
	for _, sx in { -1, 1 } do
		local W = bigWing(sx)
		local from = api.count()
		for j, s in REWARD.PHOENIX do
			local S = W * CFrame.new(sx * 0.12, -0.05, 0) * ANG(0, 0, -sx * s[1])
			local L, wd, rag = s[2], s[3], s[4]
			local b = L * 0.3
			-- the red rim: a short point back to the spine and the long one out, its ragged side outward on both wings
			local o0 = api.count()
			spike(api, R, S * CFrame.new(0, b / 2, 0) * ANG(0, 0, PI), wd, b, 0.12, 0, 0, 0, "berry_red")
			local tip = L - b
			if sx > 0 then
				spike(api, R, S, wd, tip, 0.12, 0, b + tip / 2, 0, "berry_red", tip * rag)
			else
				spike(api, R, S, wd, tip * rag, 0.12, 0, b + tip * rag / 2, 0, "berry_red", tip)
			end
			api.anim(o0, turnF(S, 8, function(f)
				return 0, 0, osc(f, 8, 0.05, j * 0.9)
			end))
			-- the fire within: thicker (it shows on both faces), aglow, flickering
			local i0 = api.count()
			local Sb = S * CFrame.new(0, b, 0)
			REWARD.flame(api, R, Sb, wd * 0.64, tip * 0.82, 0.18, tip * 0.41, c)
			if s[5] == 1 then
				fput(api, R, Sb, 0.16, tip * 0.5, 0.26, 0, tip * 0.22, 0, a)
				api.glow()
			end
			api.anim(i0, turnF(Sb, 4, function(f)
				return 0, 0, osc(f, 4, 0.1, j * 1.7)
			end))
		end
		api.anim(from, flapF(W, sx, 16, 0.13, 0.08))
		-- an ember rising off the wing, out of sight in the torso between
		local base = (W * CFrame.new(sx * 1.35, 1.5, 0.12)).Position
		local path: { Vector3 } = { HIDE_ROOT }
		for f = 1, 7 do
			path[f + 1] = base + Vector3.new(sx * 0.05 * f + 0.1 * sin(f * 1.3), 0.32 * f, -0.04 * f)
		end
		local k = if sx > 0 then 1 else 5
		local e0 = api.count()
		local p0 = path[k % 8 + 1]
		api.add(R, 0.17, 0.17, 0.17, p0.X, p0.Y, p0.Z, a, ANG(PI / 4, PI / 4, 0))
		api.glow()
		api.anim(e0, alongF(path, k))
	end
	-- the tongue of flame at the spine, between the wings' roots
	local C = CFrame.new(0, 2.0, -0.72) * ANG(-0.26, 0, 0)
	local c0 = api.count()
	REWARD.flame(api, R, C, 0.5, 0.86, 0.16, 0.42, c)
	api.anim(c0, turnF(C, 4, function(f)
		return 0, 0, osc(f, 4, 0.1)
	end))
end

-- Lucky Spin, very rare: a gold wand with an emerald pommel and gold grip rings, a green ribbon bow, and on top a gold
-- horseshoe (open side up, to hold the luck) cradling a glowing star. The star pulses (its rays flare out and draw
-- back into it), three little stars orbit it, and a glint twinkles on the horseshoe.
HAND.horseshoe_wand = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fcyl(api, A, G, 0.17, 2.5, 0.8, c)
	for _, s in { -0.12, 0.2 } do
		fcyl(api, A, G, 0.2, 0.07, s, "plate_gold")
	end
	fball(api, A, G, 0.26, 0, -0.5, 0, a)
	api.glow()
	fcyl(api, A, G, 0.26, 0.12, 2.0, "plate_gold")
	-- the bow under the horseshoe
	local B = G * CFrame.new(0, 1.84, 0) * ANG(0, PI / 4, 0)
	fput(api, A, B, 0.26, 0.17, 0.07, -0.15, 0.02, 0.09, a, ANG(0, 0, 0.4))
	fput(api, A, B, 0.26, 0.17, 0.07, 0.15, 0.02, 0.09, a, ANG(0, 0, -0.4))
	fput(api, A, B, 0.07, 0.24, 0.06, -0.08, -0.14, 0.09, a, ANG(0, 0, -0.35))
	fput(api, A, B, 0.07, 0.24, 0.06, 0.08, -0.14, 0.09, a, ANG(0, 0, 0.35))
	-- the horseshoe: a U of gold turned to the camera, open at the top, its ends flared
	local Hs = G * CFrame.new(0, 2.58, 0) * ANG(0, PI / 4, 0)
	local r = 0.48
	for k = 0, 4 do
		local ang = PI + (k + 0.5) * PI / 5
		fput(api, A, Hs, 2 * r * math.tan(PI / 10) + 0.06, 0.2, 0.13, cos(ang) * r, sin(ang) * r, 0, c, ANG(0, 0, ang + PI / 2))
	end
	for _, sx in { -1, 1 } do
		fput(api, A, Hs, 0.2, 0.4, 0.13, sx * r, 0.2, 0, c)
		fput(api, A, Hs, 0.3, 0.11, 0.14, sx * (r + 0.05), 0.42, 0, c)
	end
	-- the star in it, and its rays: out at rest, flaring, then drawn back inside it
	local St = Hs * CFrame.new(0, 0.06, 0.05)
	star(api, A, St, 0.17, 0.12, "yellow", "white", true)
	local out = { 0, 0.06, 0, -0.16, -0.33, -0.33, -0.33, -0.16 }
	for k = 0, 7 do
		local ang = k * PI / 4 + PI / 8
		local dir = St:VectorToWorldSpace(Vector3.new(cos(ang), sin(ang), 0))
		local from = api.count()
		fput(api, A, St, 0.06, 0.14, 0.03, cos(ang) * 0.39, sin(ang) * 0.39, 0.03, "yellow", ANG(0, 0, ang - PI / 2))
		api.glow()
		api.anim(from, moveF(8, function(f)
			return dir * out[f]
		end))
	end
	-- three little stars orbiting it, round its front and behind it
	local function at(ang: number): Vector3
		return (St * CFrame.new(cos(ang) * 0.76, sin(ang) * 0.24, sin(ang) * 0.5)).Position
	end
	for k = 0, 2 do
		local a0 = k * 2 * PI / 3 + 0.3
		local from = api.count()
		sparkle(api, A, CFrame.new(at(a0)) * St.Rotation, 0.26, "yellow")
		api.anim(from, REWARD.orbitF(8, a0, 2 * PI / 3, at))
	end
	local g = (Hs * CFrame.new(-0.46, 0.36, 0.12)).Position
	glint(api, A, g.X, g.Y, g.Z, 0.3, HIDE_ARM, "00000120")
end

-- Lucky Spin, very rare: a gold chain round the neck and down the chest with four charms hanging off it on gold rings:
-- a four-leaf clover, a glowing star, a horseshoe and a little rainbow on a cloud. The charms swing on their rings,
-- each on its own beat, and glints twinkle over them.
NECK.lucky_charm_necklace = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.62, 0.1, 1.12, 0, 2.42, 0, c)
	local chain = { { -0.62, 2.38, 0.58 }, { -0.5, 2.12, 0.72 }, { -0.25, 1.95, 0.79 }, { 0, 1.9, 0.8 }, { 0.25, 1.95, 0.79 }, { 0.5, 2.12, 0.72 }, { 0.62, 2.38, 0.58 } }
	for k = 1, #chain - 1 do
		local p, q = chain[k], chain[k + 1]
		link(api, R, p[1], p[2], p[3], q[1], q[2], q[3], 0.09, c)
	end
	-- { x, the ring's y, the charm }
	local charms: { { any } } = { { -0.5, 2.12, "clover" }, { -0.17, 1.93, "star" }, { 0.17, 1.93, "horseshoe" }, { 0.5, 2.12, "rainbow" } }
	for i, ch in charms do
		local x, ry, kind = ch[1] :: number, ch[2] :: number, ch[3] :: string
		local Rg = CFrame.new(x, ry, 0.8) * ANG(0, 0.45, 0)
		local from = api.count()
		api.ball(R, 0.11, x, ry, 0.8, c)
		if kind == "clover" then
			REWARD.clover(api, R, Rg * CFrame.new(0, -0.27, 0.03), 0.22, 0.06, a)
		elseif kind == "star" then
			star(api, R, Rg * CFrame.new(0, -0.32, 0.08), 0.15, 0.07, "yellow", "white", true)
		elseif kind == "horseshoe" then
			fput(api, R, Rg, 0.4, 0.11, 0.06, 0, -0.46, 0.05, c)
			fput(api, R, Rg, 0.11, 0.32, 0.06, -0.145, -0.33, 0.05, c)
			fput(api, R, Rg, 0.11, 0.32, 0.06, 0.145, -0.33, 0.05, c)
		else
			local Rb = Rg * CFrame.new(0, -0.26, 0.03)
			fdisc(api, R, Rb, 0.46, 0.05, 0, 0, 0, "berry_red")
			fdisc(api, R, Rb, 0.32, 0.05, 0, 0, 0.01, "yellow")
			fdisc(api, R, Rb, 0.18, 0.05, 0, 0, 0.02, "r_rare")
			fput(api, R, Rb, 0.5, 0.25, 0.06, 0, -0.115, 0.04, c)
			fball(api, R, Rb, 0.2, -0.22, -0.06, 0.05, "white")
			fball(api, R, Rb, 0.2, 0.22, -0.06, 0.05, "white")
		end
		api.anim(from, turnF(Rg, 8, function(f)
			return 0, 0, osc(f, 8, 0.28, i * 1.6)
		end))
	end
	glint(api, R, -0.32, 1.76, 0.94, 0.3, HIDE_ROOT, "12000000")
	glint(api, R, 0.36, 1.72, 0.94, 0.28, HIDE_ROOT, "00001200")
end

-- Streak (7 days): a golden rolling pin held up like a scepter: ruby handles with gold knobs and collars, the barrel
-- ringed with engraved bands near its ends (rubies set in them) and a ruby in gold in its middle. A glint of light runs
-- up the barrel on the camera's side and a sparkle flashes at the top when it gets there.
HAND.golden_rolling_pin = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fcyl(api, A, G, 0.2, 0.56, 0, a)
	fball(api, A, G, 0.3, 0, -0.34, 0, a)
	fball(api, A, G, 0.14, 0, -0.5, 0, c)
	fcyl(api, A, G, 0.3, 0.1, 0.3, c)
	fcyl(api, A, G, 0.56, 1.5, 1.1, c)
	for _, s in { 0.5, 0.62, 1.58, 1.7 } do
		fcyl(api, A, G, 0.6, 0.05, s, "plate_gold")
	end
	fcyl(api, A, G, 0.3, 0.1, 1.9, c)
	fcyl(api, A, G, 0.2, 0.5, 2.18, a)
	fball(api, A, G, 0.3, 0, 2.48, 0, a)
	fball(api, A, G, 0.14, 0, 2.66, 0, c)
	-- rubies: one in gold in the middle of the barrel, small ones in the bands, on the camera's side
	local M = G * CFrame.new(0, 1.1, 0) * ANG(0, PI / 4, 0)
	fdisc(api, A, M, 0.3, 0.06, 0, 0, 0.27, "plate_gold")
	fput(api, A, M, 0.2, 0.2, 0.08, 0, 0, 0.3, a, DIAMOND)
	api.glow()
	for _, s in { 0.56, 1.64 } do
		fball(api, A, M, 0.1, 0, s - 1.1, 0.3, a)
	end
	-- the glint: up the barrel's camera side in five steps, then inside it for three
	local cam = G:VectorToObjectSpace(Vector3.new(0.61, 0.5, 0.61))
	local rad = Vector3.new(cam.X, 0, cam.Z).Unit * 0.27
	fput(api, A, G, 0.08, 1.3, 0.08, rad.X * 0.97, 1.1, rad.Z * 0.97, "yellow")
	local path: { Vector3 } = {}
	for _, s in { 0.5, 0.78, 1.06, 1.34, 1.62 } do
		table.insert(path, (G * CFrame.new(rad.X, s, rad.Z)).Position)
	end
	local inside = (G * CFrame.new(0, 1.1, 0)).Position
	for _ = 6, 8 do
		table.insert(path, inside)
	end
	local from = api.count()
	fput(api, A, CFrame.new(path[2]) * G.Rotation, 0.12, 0.3, 0.12, 0, 0, 0, "white")
	api.glow()
	api.anim(from, alongF(path, 1))
	local tip = (G * CFrame.new(0.12, 2.5, 0.16)).Position
	glint(api, A, tip.X, tip.Y, tip.Z, 0.34, HIDE_ARM, "00012000")
end

------------------------------------------------------------------ the shop's animated pieces

-- The shop's dearest pieces (Data/Cosmetics shop items of rarity Mythic and Divine; the user: "lean more towards
-- cute accessories"): little animals and playful sweets that move like the reward looks (Api.anim on the world's
-- clock, several parts on loops of their own); still pictures show the rest pose, kept inside the customization screen's frame
-- (the screen's frame).

-- n frames for a part drawn out of sight at `rest`: on frame f it moves to at[f] when there is one, else stays hidden
function REWARD.showF(n: number, rest: Vector3, at: { [number]: Vector3 }): { CFrame }
	return moveF(n, function(f)
		local p = at[f]
		return if p then p - rest else Vector3.zero
	end)
end

-- n frames for a part drawn in place: shown on the frames `on` lists, moved by (hide - pos) out of sight the rest
function REWARD.onlyF(n: number, pos: Vector3, hide: Vector3, on: { [number]: boolean }): { CFrame }
	return moveF(n, function(f)
		return if on[f] then Vector3.zero else hide - pos
	end)
end

-- the rat's moves: the head dipping to the cheese (radians, three quick bites then a rest) while the paws lift it
-- (studs), over 8 frames; the ears' twitches (radians, outward) over 24
REWARD.RAT_NIBBLE = { 0, 0.34, 0.06, 0.34, 0.06, 0.34, 0, 0 }
REWARD.RAT_LIFT = { 0, 0.08, 0.02, 0.08, 0.02, 0.08, 0, 0 }
REWARD.RAT_TWITCH = {
	[1] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.55, 0.15, 0.55, 0, 0, 0, 0, 0, 0, 0 },
	[-1] = { 0, 0, 0, 0, 0.5, 0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
} :: { [number]: { number } }

-- Shop, Divine: a little grey rat sitting up on the hair, facing front: round haunches and chest, pink feet,
-- big round ears (pink inside), black bead eyes with a glint, a round snout with a pink nose and whiskers, and a long
-- pink tail over the back of the hair, down the back of the head and curling up at its tip. Its pink paws hold a
-- wedge of cheese. It nibbles (the head dips to the cheese as the paws lift it: three quick bites, then a rest), the
-- tail swishes from side to side (its lower half a beat behind), and now and then an ear twitches.
HAT.rat_buddy = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	-- the body: round haunches, a chest, the feet in front
	api.ball(H, 1.0, 0, t + 0.42, -0.22, c)
	api.ball(H, 0.8, 0, t + 0.74, -0.02, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.24, 0.12, 0.36, sx * 0.27, t + 0.05, 0.22, a)
	end
	-- the tail: from the rump over the hair and down the back of the head (behind the longest bob), curling up at the
	-- tip on the camera's side; it swings about its root, its lower half about its middle a beat behind
	local P = {
		Vector3.new(0.05, t + 0.14, -0.6),
		Vector3.new(0.18, t + 0.08, -1.0),
		Vector3.new(0.3, t - 0.06, -1.32),
		Vector3.new(0.4, t - 0.5, -1.34),
		Vector3.new(0.46, t - 0.92, -1.34),
		Vector3.new(0.52, t - 1.26, -1.34),
		Vector3.new(0.7, t - 1.44, -1.34),
		Vector3.new(0.9, t - 1.36, -1.33),
		Vector3.new(0.94, t - 1.14, -1.32),
	}
	local tail = api.count()
	local lower = tail
	for k = 1, #P - 1 do
		if k == 5 then
			lower = api.count()
		end
		local p, q = P[k], P[k + 1]
		link(api, H, p.X, p.Y, p.Z, q.X, q.Y, q.Z, 0.17 - 0.01 * k, a)
	end
	api.anim(lower, turnF(CFrame.new(P[5]), 12, function(f)
		return 0, 0, osc(f, 12, 0.32, -1.3)
	end))
	api.anim(tail, turnF(CFrame.new(P[1]), 12, function(f)
		return 0, 0, osc(f, 12, 0.2)
	end))
	-- the paws and the cheese (a wedge turned to the camera, holes in it), lifted to the mouth on each bite
	local paws = api.count()
	local C = CFrame.new(0.02, t + 0.68, 0.6) * ANG(0, 0.6, 0)
	tri(api, H, C, 0.5, 0.36, 0.24, 0, 0, 0, "yellow")
	fdisc(api, H, C, 0.11, 0.04, 0.1, -0.08, 0.12, "sponge")
	fdisc(api, H, C, 0.08, 0.04, -0.06, -0.12, 0.12, "sponge")
	fdisc(api, H, C, 0.07, 0.04, 0.17, 0.06, 0.12, "sponge")
	for _, sx in { -1, 1 } do
		api.ball(H, 0.22, sx * 0.22, t + 0.74, 0.54, a)
	end
	api.anim(paws, moveF(8, function(f)
		return Vector3.new(0, REWARD.RAT_LIFT[f], 0)
	end))
	-- the head, dipping from the neck: snout, nose, eyes and glints, whiskers, ears
	local head = api.count()
	api.ball(H, 0.68, 0, t + 1.12, 0.1, c)
	api.ball(H, 0.4, 0, t + 1.04, 0.42, c)
	api.ball(H, 0.18, 0, t + 1.07, 0.63, a)
	for _, sx in { -1, 1 } do
		api.ball(H, 0.19, sx * 0.16, t + 1.2, 0.38, "black")
		api.add(H, 0.07, 0.07, 0.06, sx * 0.16 + 0.04, t + 1.25, 0.47, "white")
		for _, k in { -1, 1 } do
			api.add(H, 0.5, 0.06, 0.06, sx * 0.44, t + 1.02 + k * 0.07, 0.4, "white", ANG(0, sx * 0.35, sx * k * 0.22))
		end
		local E = CFrame.new(sx * 0.29, t + 1.38, -0.02) * ANG(0, sx * 0.25, -sx * 0.3) * ANG(-0.35, 0, 0)
		local ear = api.count()
		fdisc(api, H, E, 0.54, 0.08, 0, 0, 0, c)
		fdisc(api, H, E, 0.38, 0.06, 0, 0, 0.05, a)
		local tw = REWARD.RAT_TWITCH[sx]
		api.anim(ear, turnF(E * CFrame.new(0, -0.22, 0), 24, function(f)
			return 0, 0, -sx * tw[f]
		end))
	end
	api.anim(head, turnF(CFrame.new(0, t + 0.92, 0.06), 8, function(f)
		return REWARD.RAT_NIBBLE[f], 0, 0
	end))
end

-- the chick's moves over 16 frames: ducking into the nest and popping up (studs), its wings flapping and its beak
-- opening to peep (radians); the egg's wobble over 12
REWARD.CHICK_DUCK = { -0.52, -0.52, -0.36, -0.08, 0.05, 0, 0, 0, 0, 0, 0, 0, -0.12, -0.36, -0.52, -0.52 }
REWARD.CHICK_FLAP = { 0, 0, 0, 0, 0.8, 0, 0.8, 0, 0, 0, 0.8, 0.3, 0, 0, 0, 0 }
REWARD.CHICK_PEEP = { 0, 0, 0, 0, 0, 0, 0, 0.6, 0, 0.6, 0, 0, 0, 0, 0, 0 }
REWARD.EGG_WOBBLE = { 0, 0, 0, 0, 0, 0, 0, 0.3, -0.24, 0.14, 0, 0 }

-- Shop, Divine: a straw nest on the hair (a low bowl, a fluffy rim, darker straws poking out of it) with a
-- speckled blue egg in it on the camera's side and a fluffy yellow chick: a round body, a round head with a tuft,
-- black eyes with a glint, an orange beak and little wings. The chick ducks into the nest (its tuft and eyes peeking
-- over the rim), pops up, flaps its wings and peeps (the beak opens) and ducks again; the egg wobbles on its own beat.
HAT.chick_nest = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local z0 = -0.05
	api.cyl(H, 1.24, 0.24, 0, t + 0.1, z0, c)
	api.cyl(H, 0.96, 0.06, 0, t + 0.24, z0, "wood_dark")
	for k = 0, 11 do
		local ang = k * PI / 6
		api.ball(H, 0.36, cos(ang) * 0.58, t + 0.3 + (k % 2) * 0.04, z0 + sin(ang) * 0.58, c)
	end
	for k = 0, 8 do
		local ang = k * 2 * PI / 9 + 0.3
		local tilt = if k % 2 == 0 then 0.3 else -0.25
		api.add(H, 0.44, 0.08, 0.08, cos(ang) * 0.7, t + 0.33 + 0.06 * sin(k * 2.3), z0 + sin(ang) * 0.7, "wood_dark", ANG(0, PI / 2 - ang + 0.5, tilt))
	end
	-- the egg, speckled, wobbling now and then
	local ex, ez = 0.4, z0 + 0.36
	local egg = api.count()
	api.ball(H, 0.34, ex, t + 0.4, ez, "sky_day")
	api.ball(H, 0.26, ex, t + 0.55, ez, "sky_day")
	local Eg = CFrame.new(ex, t + 0.4, ez) * ANG(0, 0.8, 0)
	fput(api, H, Eg, 0.07, 0.07, 0.04, -0.06, 0.05, 0.165, "wood_dark")
	fput(api, H, Eg, 0.07, 0.07, 0.04, 0.08, -0.04, 0.16, "wood_dark")
	fput(api, H, Eg, 0.06, 0.06, 0.04, 0.02, 0.2, 0.12, "wood_dark")
	api.anim(egg, turnF(CFrame.new(ex, t + 0.23, ez), 12, function(f)
		return 0, 0, REWARD.EGG_WOBBLE[f]
	end))
	-- the chick, drawn popped up
	local Ck = CFrame.new(0, t + 0.56, z0 + 0.04)
	local chick = api.count()
	fball(api, H, Ck, 0.76, 0, 0, 0, a)
	fball(api, H, Ck, 0.6, 0, 0.46, 0.06, a)
	fput(api, H, Ck, 0.1, 0.26, 0.1, 0.02, 0.8, 0.08, a, ANG(0.5, 0, -0.35))
	fput(api, H, Ck, 0.08, 0.16, 0.08, -0.08, 0.78, 0.02, a, ANG(0.3, 0, 0.5))
	for _, sx in { -1, 1 } do
		fball(api, H, Ck, 0.17, sx * 0.13, 0.53, 0.32, "black")
		fput(api, H, Ck, 0.06, 0.06, 0.05, sx * 0.13 + 0.03, 0.57, 0.38, "white")
	end
	fput(api, H, Ck, 0.22, 0.08, 0.18, 0, 0.42, 0.42, "orange")
	local beak = api.count()
	fput(api, H, Ck, 0.18, 0.07, 0.15, 0, 0.35, 0.41, "orange")
	api.anim(beak, turnF(Ck * CFrame.new(0, 0.39, 0.33), 16, function(f)
		return REWARD.CHICK_PEEP[f], 0, 0
	end))
	for _, sx in { -1, 1 } do
		local Wg = Ck * CFrame.new(sx * 0.36, 0.14, 0)
		local w0 = api.count()
		fput(api, H, Wg, 0.12, 0.34, 0.3, sx * 0.04, -0.14, 0, a, ANG(0, 0, sx * 0.2))
		api.anim(w0, turnF(Wg, 16, function(f)
			return 0, 0, sx * REWARD.CHICK_FLAP[f]
		end))
	end
	api.anim(chick, moveF(16, function(f)
		return Vector3.new(0, REWARD.CHICK_DUCK[f], 0)
	end))
end

-- Shop, Mythic: a wad of pink gum at the lips blowing a bubble: it swells over seven frames (a white shine on
-- it), pops in a white flash with bits of gum flying out, and starts again small (12 frames). The two biggest bubbles
-- show only while it moves (out of sight in the head at rest), so still pictures stay inside the customization screen's frame.
REWARD.GUM = {
	-- { across, the frame it shows on, 1: out of sight at rest }
	{ 0.3, 1, 0 },
	{ 0.42, 2, 0 },
	{ 0.54, 3, 0 },
	{ 0.66, 4, 0 },
	{ 0.76, 5, 0 },
	{ 0.86, 6, 1 },
	{ 0.94, 7, 1 },
} :: { { number } }
FACE.bubble_gum = function(api, c, a, _ctx)
	local H = api.HEAD
	local y, z = 2.85, 1.0
	api.ball(H, 0.26, 0, y, z + 0.04, c)
	local up = Vector3.new(0.15, 0.62, 0.77).Unit
	local big = Vector3.zero
	for _, g in REWARD.GUM do
		local d, fr = g[1], g[2]
		local p = Vector3.new(0, y - d * 0.06, z + d * 0.35)
		big = p
		local gd = math.max(0.1, d * 0.2)
		local s = p + up * (d / 2 - gd * 0.15)
		local from = api.count()
		if g[3] == 1 then
			api.ball(H, d, HIDE_HEAD.X, HIDE_HEAD.Y, HIDE_HEAD.Z, c)
			local hs = HIDE_HEAD + (s - p)
			api.ball(H, gd, hs.X, hs.Y, hs.Z, a)
			api.anim(from, REWARD.showF(12, HIDE_HEAD, { [fr] = p }))
		else
			api.ball(H, d, p.X, p.Y, p.Z, c)
			api.ball(H, gd, s.X, s.Y, s.Z, a)
			api.anim(from, REWARD.onlyF(12, p, HIDE_HEAD, { [fr] = true }))
		end
	end
	-- the pop: a white flash on frame 8, bits of gum flying out on 8 and 9 (out of sight in the head the rest)
	local S = CFrame.new(big) * FACE_CAM
	local from = api.count()
	REWARD.twinkle(api, H, CFrame.new(HIDE_HEAD) * S.Rotation, 1.1, a, a)
	api.anim(from, REWARD.showF(12, HIDE_HEAD, { [8] = big }))
	for k = 0, 5 do
		local ang = k * PI / 3 + 0.4
		local dir = S:VectorToWorldSpace(Vector3.new(cos(ang), sin(ang), 0.35))
		local b0 = api.count()
		api.add(H, 0.16, 0.16, 0.12, HIDE_HEAD.X, HIDE_HEAD.Y, HIDE_HEAD.Z, c, S.Rotation * ANG(0, 0, ang + PI / 4))
		api.anim(b0, REWARD.showF(12, HIDE_HEAD, { [8] = big + dir * 0.55, [9] = big + dir * 0.85 - Vector3.new(0, 0.12, 0) }))
	end
end

-- the kitten's moves: a slow breath (studs, 16 frames), its tail tip's flick and an ear's twitch (radians, 24)
REWARD.KITTEN_BREATH = { 0, 0.02, 0.04, 0.06, 0.07, 0.07, 0.06, 0.04, 0.02, 0, -0.01, -0.02, -0.02, -0.02, -0.01, 0 }
REWARD.KITTEN_FLICK = { 0, 0, 0, 0, 0, 0, 0, 0, 0.5, 0.2, 0.6, 0.15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
REWARD.KITTEN_TWITCH = { 0, 0, 0, 0.45, 0.1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.45, 0, 0.4, 0, 0, 0 }

-- a glowing "z" facing Z's front, s across: a bar along its top and its bottom and one from corner to corner
function REWARD.zee(api: Api, bone: number, Z: CFrame, s: number, color: string)
	local w = math.max(0.08, s * 0.26)
	fput(api, bone, Z, s, w, 0.1, 0, (s - w) / 2, 0, color)
	api.glow()
	fput(api, bone, Z, s, w, 0.1, 0, -(s - w) / 2, 0, color)
	api.glow()
	fput(api, bone, Z, w, (s - w) * 1.3, 0.1, 0, 0, 0, color, ANG(0, 0, -PI / 4))
	api.glow()
end

-- Shop, Divine: a ginger kitten curled up asleep on the hair: a round loaf of a body, its head resting on cream
-- paws at the front toward the camera (tabby stripes on its brow, pink inner ears, a cream muzzle with a pink nose,
-- shut eyes and rosy cheeks), a cream belly, its tail wrapped round the front with a cream tip. It breathes (its body
-- rises and falls slowly), the tail tip flicks and an ear twitches now and then, and little z's float up off it.
HAT.sleepy_kitten = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	-- the body and its cream belly, breathing
	local body = api.count()
	api.ball(H, 0.96, -0.18, t + 0.34, -0.2, c)
	api.ball(H, 0.88, 0.18, t + 0.3, -0.12, c)
	api.ball(H, 0.5, 0.2, t + 0.2, 0.22, a)
	api.anim(body, moveF(16, function(f)
		return Vector3.new(0, REWARD.KITTEN_BREATH[f], 0)
	end))
	-- the paws the head rests on
	api.ball(H, 0.26, 0.06, t + 0.12, 0.56, a)
	api.ball(H, 0.26, 0.48, t + 0.12, 0.52, a)
	-- the head, its face turned toward the camera: a cream muzzle, a pink nose, shut eyes, pink cheeks; big ears
	local Hd = CFrame.new(0.26, t + 0.58, 0.4) * ANG(0, 0.35, 0) * ANG(-0.25, 0, 0.1)
	fball(api, H, Hd, 0.8, 0, 0, 0, c)
	fball(api, H, Hd, 0.36, 0, -0.15, 0.3, a)
	fball(api, H, Hd, 0.13, 0, -0.06, 0.46, "pink")
	for _, sx in { -1, 1 } do
		fput(api, H, Hd, 0.2, 0.06, 0.05, sx * 0.16, 0.06, 0.37, "ink", ANG(0, 0, sx * 0.12))
		fdisc(api, H, Hd, 0.15, 0.04, sx * 0.26, -0.1, 0.3, "pink")
	end
	for _, sx in { -1, 1 } do
		local E = Hd * CFrame.new(sx * 0.22, 0.3, -0.04) * ANG(0, 0, -sx * 0.22)
		local e0 = api.count()
		spike(api, H, E, 0.4, 0.42, 0.12, 0, 0.17, 0, c)
		spike(api, H, E, 0.22, 0.24, 0.12, 0, 0.12, 0.05, "pink")
		if sx > 0 then
			api.anim(e0, turnF(E, 24, function(f)
				return 0, 0, -REWARD.KITTEN_TWITCH[f]
			end))
		end
	end
	-- the tail, wrapped round the front from behind, its cream tip flicking now and then
	local T = {
		Vector3.new(-0.5, t + 0.22, -0.46),
		Vector3.new(-0.74, t + 0.16, -0.08),
		Vector3.new(-0.62, t + 0.12, 0.3),
		Vector3.new(-0.32, t + 0.1, 0.52),
		Vector3.new(-0.04, t + 0.12, 0.6),
		Vector3.new(0.12, t + 0.2, 0.62),
	}
	local tip = 0
	for k = 1, #T - 1 do
		if k == 4 then
			tip = api.count()
		end
		local p, q = T[k], T[k + 1]
		local col = if k == #T - 1 then a else c
		local w = if k >= 4 then 0.2 else 0.22
		link(api, H, p.X, p.Y, p.Z, q.X, q.Y, q.Z, w, col)
		api.ball(H, w, q.X, q.Y, q.Z, col)
	end
	api.anim(tip, turnF(CFrame.new(T[4]), 24, function(f)
		return 0, 0, REWARD.KITTEN_FLICK[f]
	end))
	-- z's floating up off it on a loop of 12 (gone into the head for the last three), small to big
	local path: { Vector3 } = {}
	for f = 1, 9 do
		path[f] = Vector3.new(0.52 + 0.06 * f + 0.07 * sin(f * 1.1), t + 1.0 + 0.13 * f, 0.36 - 0.02 * f)
	end
	for f = 10, 12 do
		path[f] = HIDE_HEAD
	end
	for i, k in { 0, 4, 8 } do
		local p0 = path[k + 1]
		local z0 = api.count()
		REWARD.zee(api, H, CFrame.new(p0) * ANG(0, 0.3, 0), 0.22 + 0.07 * i, "white")
		api.anim(z0, alongF(path, k))
	end
end

-- the boppers' bounce: each heart springs up and down its stalk (studs) as the stalk sways from its foot, the two out
-- of step (8 frames and 12)
REWARD.BOP8 = { 0, 0.12, 0.16, 0.08, -0.06, -0.1, -0.04, 0.04 }
REWARD.BOP12 = { 0, 0.08, 0.14, 0.16, 0.1, 0, -0.08, -0.1, -0.06, 0, 0.04, 0.02 }

-- Shop, Mythic: a red headband over the hair and down to the ears with two springy antennae, each a pink spring (a
-- zigzag up a stalk leaning out) topped with a puffy red heart (a pink heart over it and a white shine). The hearts
-- bounce on their springs (the coils stretching with them) and the stalks sway from their feet, the two out of step.
HAT.heart_boppers = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	api.add(H, 2.66, 0.14, 0.28, 0, t + 0.07, 0.15, c)
	for _, sx in { -1, 1 } do
		api.add(H, 0.12, t + 0.14 - 3.5, 0.28, sx * 1.27, (t + 0.14 + 3.5) / 2, 0.15, c)
	end
	local side = Vector3.new(0.707, 0, -0.707)
	for i, sx in { -1, 1 } do
		local base = Vector3.new(sx * 0.48, t + 0.12, 0.15)
		local U = Vector3.new(sx * sin(0.32), cos(0.32), 0)
		local bop = if i == 1 then REWARD.BOP8 else REWARD.BOP12
		local n = #bop
		local stalk = api.count()
		-- the spring: a zigzag up the stalk across the camera's view, each coil moving with its share of the bounce
		local prev = base
		for k = 1, 6 do
			local q = base + U * (0.13 * k) + side * (if k % 2 == 1 then 0.12 else -0.12)
			if k == 6 then
				q = base + U * 0.8
			end
			local l0 = api.count()
			link(api, H, prev.X, prev.Y, prev.Z, q.X, q.Y, q.Z, 0.08, a)
			api.anim(l0, moveF(n, function(f)
				return U * (bop[f] * (k - 0.5) / 6)
			end))
			prev = q
		end
		-- the heart: turned only partway to the camera, so its face catches the light
		local Hf = CFrame.new(base + U * 1.06) * ANG(0, 0.35, 0) * ANG(-0.45, 0, 0)
		local hrt = api.count()
		heart(api, H, Hf, 0.72, 0.22, c)
		heart(api, H, Hf * CFrame.new(-0.03, 0.04, 0.08), 0.44, 0.12, a)
		fball(api, H, Hf, 0.12, -0.17, 0.13, 0.16, "white")
		api.anim(hrt, moveF(n, function(f)
			return U * bop[f]
		end))
		api.anim(stalk, turnF(CFrame.new(base), n, function(f)
			return 0, 0, osc(f, n, 0.14, i * 1.7)
		end))
	end
end

-- Shop, Mythic: rosy cheeks (a pink blush) and little hearts, red and pink, that pop out by the cheeks, float up past
-- the face and are gone, two a side on staggered loops (10 frames: seven rising, three gone into the head).
REWARD.FLOATY = {
	-- { side, where it rests along its path, across, its colour (1 the main one, 2 the accent) }
	{ 1, 0, 0.46, 1 },
	{ 1, 3, 0.38, 2 },
	{ 1, 6, 0.42, 1 },
	{ -1, 1, 0.42, 2 },
	{ -1, 4, 0.46, 1 },
	{ -1, 7, 0.38, 2 },
} :: { { number } }
FACE.floaty_hearts = function(api, c, a, _ctx)
	local H = api.HEAD
	for _, sx in { -1, 1 } do
		disc(api, H, 0.3, 0.04, sx * 0.58, 2.98, 1.01, a)
		disc(api, H, 0.3, 0.04, sx * 0.72, 2.98, 1.01, a)
	end
	for i, fl in REWARD.FLOATY do
		local sx, k, s = fl[1], fl[2], fl[3]
		-- out by the cheek in front of the face (clear of the eyes), rising and drifting out; turned only partway to
		-- the camera, so their faces catch the light
		local path: { Vector3 } = {}
		for f = 1, 7 do
			path[f] = Vector3.new(sx * (0.82 + 0.025 * f) + 0.05 * sin(f * 1.4 + i), 2.92 + 0.2 * f, 1.12 - 0.02 * f)
		end
		for f = 8, 10 do
			path[f] = HIDE_HEAD
		end
		local p0 = path[k + 1]
		local from = api.count()
		heart(api, H, CFrame.new(p0) * ANG(0, 0.3, 0) * ANG(-0.4, 0, 0), s, 0.1, if fl[4] == 1 then c else a)
		api.anim(from, alongF(path, k))
	end
end

-- the bunny's sniff: the nose bobbing up (studs) in quick pairs, 12 frames; the whiskers twitch with it
REWARD.SNIFF = { 0, 0.07, 0, 0.07, 0, 0, 0, 0, 0.07, 0, 0, 0 }

-- Shop, Mythic: a pink bunny nose (a little heart with a white shine) over a "Y" of a mouth, two white buck teeth
-- under it, three long white whiskers a side poking out past the cheeks, and pink cheeks. The nose sniffs (quick bobs
-- up and down) and the whiskers twitch with it.
FACE.bunny_nose = function(api, c, a, _ctx)
	local H = api.HEAD
	for _, sx in { -1, 1 } do
		disc(api, H, 0.3, 0.04, sx * 0.66, 2.98, 1.01, c)
	end
	api.add(H, 0.06, 0.12, 0.04, 0, 2.84, 1.02, "ink")
	api.add(H, 0.16, 0.06, 0.04, -0.08, 2.77, 1.02, "ink", ANG(0, 0, -0.4))
	api.add(H, 0.16, 0.06, 0.04, 0.08, 2.77, 1.02, "ink", ANG(0, 0, 0.4))
	for _, sx in { -1, 1 } do
		api.add(H, 0.13, 0.18, 0.06, sx * 0.07, 2.65, 1.02, a)
	end
	local nose = api.count()
	heart(api, H, CFrame.new(0, 3.1, 1.04), 0.42, 0.12, c)
	api.ball(H, 0.1, -0.08, 3.15, 1.1, a)
	api.anim(nose, moveF(12, function(f)
		return Vector3.new(0, REWARD.SNIFF[f], 0)
	end))
	for _, sx in { -1, 1 } do
		local W = CFrame.new(sx * 0.28, 2.96, 1.06)
		local w0 = api.count()
		for k = -1, 1 do
			fput(api, H, W, 0.8, 0.06, 0.05, sx * 0.42, k * 0.09, 0, a, ANG(0, 0, sx * k * 0.2))
		end
		api.anim(w0, turnF(W, 12, function(f)
			return 0, 0, sx * REWARD.SNIFF[f] * 2.5
		end))
	end
end

-- Shop, Mythic: little four-pointed sparkles round the eyes and cheeks (yellow rays round a white heart, all
-- aglow), clear of the eyes, that twinkle one after another round the face: each comes small, flares big and shrinks
-- away (10 frames).
REWARD.TWINKLES = {
	-- { x, y, z, the frame it comes on, 1: turned to the camera (the one off the side of the head) }; those on the face
	-- lie flat in front of it (the upper ones in front of the fringe), their rays clear of the eyes
	{ 0.9, 3.9, 1.22, 1, 0 },
	{ 0.84, 2.86, 1.08, 3, 0 },
	{ 0.0, 3.98, 1.22, 5, 0 },
	{ 1.25, 3.3, 0.8, 6, 1 },
	{ -0.84, 2.86, 1.08, 7, 0 },
	{ -0.9, 3.9, 1.22, 9, 0 },
} :: { { number } }
FACE.twinkle_sparkles = function(api, c, a, _ctx)
	local H = api.HEAD
	local N = 10
	for _, tw in REWARD.TWINKLES do
		local p = Vector3.new(tw[1], tw[2], tw[3])
		local f0 = tw[4]
		local f1 = f0 % N + 1
		local S = if tw[5] == 1 then CFrame.new(p) * FACE_CAM else CFrame.new(p)
		local small = api.count()
		REWARD.twinkle(api, H, S, 0.34, c, a)
		api.anim(small, REWARD.onlyF(N, p, HIDE_HEAD, { [f0] = true, [f1 % N + 1] = true }))
		local big = api.count()
		REWARD.twinkle(api, H, S, 0.6, c, a)
		api.anim(big, REWARD.onlyF(N, p, HIDE_HEAD, { [f1] = true }))
	end
end

-- Shop, Mythic: two big candy pinwheels on striped sticks rising out of a wrapped sweet on the back, up over the
-- shoulders like little wings (high enough that both show over the head): six vanes each, pink and yellow by turns
-- with a white stripe, round a white hub with a pink pin. They spin, one each way, the left one faster; a glint
-- twinkles by the camera's one.
BACK.candy_pinwheels = function(api, c, a, _ctx)
	local R = api.ROOT
	-- the sweet: a round candy in its wrapper, banded, the twisted ends out to the sides
	local sy, sz = 1.95, -0.86
	api.ball(R, 0.7, 0, sy, sz, c)
	api.cyl(R, 0.72, 0.12, 0, sy, sz, a)
	for _, sx in { -1, 1 } do
		spike(api, R, CFrame.new(sx * 0.5, sy, sz) * ANG(0, 0, sx * PI / 2), 0.44, 0.34, 0.12, 0, 0, 0, a)
	end
	for _, sx in { -1, 1 } do
		local hub = Vector3.new(sx * 1.42, 4.35, -1.6)
		local P = CFrame.new(hub) * ANG(-0.45, 0, 0)
		local base = Vector3.new(sx * 0.18, sy + 0.17, -1.15)
		local stem = (P * CFrame.new(0, 0, -0.08)).Position
		link(api, R, base.X, base.Y, base.Z, stem.X, stem.Y, stem.Z, 0.13, "white")
		for _, s in { 0.3, 0.55, 0.8 } do
			local q = base:Lerp(stem, s)
			api.ball(R, 0.17, q.X, q.Y, q.Z, c)
		end
		local from = api.count()
		for k = 0, 5 do
			local V = P * ANG(0, 0, k * PI / 3)
			tri(api, R, V, 0.56, 0.46, 0.08, 0.28, 0.23, 0, if k % 2 == 0 then c else a)
			fput(api, R, V, 0.5, 0.08, 0.1, 0.28, 0.04, 0, "white")
		end
		api.anim(from, rollF(P, if sx > 0 then 8 else 6, -sx * 2 * PI / 3))
		fball(api, R, P, 0.26, 0, 0, 0.05, "white")
		fball(api, R, P, 0.12, 0, 0, 0.16, c)
	end
	glint(api, R, 1.9, 4.95, -1.4, 0.34, HIDE_ROOT, "0001200000")
end

-- the jars' fireflies blink, each on its own loop ("1" lit, "0" dark: gone back inside the glass)
REWARD.FIREFLY_BLINK = { "111111000110", "1100111111110000", "11110100" }

-- Shop, Mythic: a green cord round the neck with three little glass jars hanging off it (green lids, a white
-- shine down the glass), a glowing yellow firefly in each. The jars sway, each firefly blinks on its own loop and one
-- more firefly drifts in a lazy loop round the front, blinking as it goes.
NECK.firefly_necklace = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.62, 0.1, 1.12, 0, 2.42, 0, c)
	local cord = { { -0.62, 2.38, 0.58 }, { -0.5, 2.12, 0.72 }, { -0.26, 1.97, 0.79 }, { 0, 1.93, 0.8 }, { 0.26, 1.97, 0.79 }, { 0.5, 2.12, 0.72 }, { 0.62, 2.38, 0.58 } }
	for k = 1, #cord - 1 do
		local p, q = cord[k], cord[k + 1]
		link(api, R, p[1], p[2], p[3], q[1], q[2], q[3], 0.09, c)
	end
	-- { x, the loop's y }
	local jars = { { -0.44, 2.07 }, { 0, 1.93 }, { 0.44, 2.07 } }
	for i, j in jars do
		local x, ry = j[1], j[2]
		local J = CFrame.new(x, ry, 0.84) * ANG(0, 0.6, 0)
		local from = api.count()
		fball(api, R, J, 0.13, 0, 0, 0, c)
		fcyl(api, R, J, 0.42, 0.12, -0.13, c)
		fcyl(api, R, J, 0.4, 0.46, -0.42, "window")
		fput(api, R, J, 0.07, 0.3, 0.06, -0.11, -0.42, 0.18, "white")
		local fly = api.count()
		fball(api, R, J, 0.24, 0.04, -0.44, 0.14, a)
		api.glow()
		local pat = REWARD.FIREFLY_BLINK[i]
		local back = J:VectorToWorldSpace(Vector3.new(0, 0, -0.18))
		api.anim(fly, moveF(#pat, function(f)
			return if string.sub(pat, f, f) == "1" then Vector3.zero else back
		end))
		api.anim(from, turnF(J, 8, function(f)
			return 0, 0, osc(f, 8, 0.12, i * 2.1)
		end))
	end
	-- the drifting firefly: a lit tail and a dark head, round a loop on the camera's side, dark two frames of twelve
	local path: { Vector3 } = {}
	for f = 1, 12 do
		local ang = 2 * PI * (f - 1) / 12
		path[f] = if f == 9 or f == 10 then HIDE_ROOT else Vector3.new(0.7 + 0.45 * cos(ang), 2.05 + 0.32 * sin(ang), 1.02 + 0.12 * sin(ang))
	end
	local d0 = api.count()
	local p0 = path[3]
	api.ball(R, 0.24, p0.X, p0.Y, p0.Z, a)
	api.glow()
	api.ball(R, 0.14, p0.X - 0.11, p0.Y + 0.08, p0.Z + 0.02, "black")
	api.anim(d0, alongF(path, 2))
end

-- Shop, Mythic: a sky-blue bubble wand held up beside the face: a handle with white grip rings and a ring on
-- top with a white shine. Bubbles of soapy glass with a white shine float up from the ring, four on staggered loops,
-- wobbling as they rise, and pop out of sight at the top.
REWARD.BUBBLES = {
	-- { across, where it rests along its path, its drift out (x), its drift back (z), its wobble's phase }
	{ 0.4, 0, 0.09, -0.04, 0 },
	{ 0.28, 2, 0.05, -0.02, 2.2 },
	{ 0.36, 5, 0.1, -0.06, 4.1 },
	{ 0.24, 7, 0.06, 0.02, 1.0 },
} :: { { number } }
HAND.bubble_wand = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fcyl(api, A, G, 0.15, 1.5, 0.48, c)
	for _, s in { -0.08, 0.22 } do
		fcyl(api, A, G, 0.18, 0.08, s, a)
	end
	fball(api, A, G, 0.2, 0, -0.3, 0, c)
	local r = 0.34
	local Rg = onShaft(1.62 + r)
	local top = (G * CFrame.new(0, 1.2, 0)).Position
	local bot = (Rg * CFrame.new(0, -r, 0)).Position
	link(api, A, top.X, top.Y, top.Z, bot.X, bot.Y, bot.Z, 0.13, c)
	hoop(api, A, Rg, r, 10, 0.12, 0.12, c)
	fput(api, A, Rg, 0.07, 0.16, 0.08, -0.2, 0.16, 0.06, a, ANG(0, 0, 0.7))
	-- the bubbles: ten frames a loop, eight rising from the ring and two out of sight in the arm
	local o = Rg.Position
	local up = Vector3.new(0.15, 0.62, 0.77).Unit
	for _, b in REWARD.BUBBLES do
		local d, k, dx, dz, ph = b[1], b[2], b[3], b[4], b[5]
		local path: { Vector3 } = {}
		for f = 1, 8 do
			path[f] = o + Vector3.new(dx * f + 0.08 * sin(f * 1.3 + ph), 0.1 + 0.27 * f, 0.04 + dz * f)
		end
		path[9], path[10] = HIDE_ARM, HIDE_ARM
		local from = api.count()
		local p0 = path[k + 1]
		api.ball(A, d, p0.X, p0.Y, p0.Z, "window")
		local gd = math.max(0.09, d * 0.28)
		local s = p0 + up * (d / 2 - gd * 0.2)
		api.ball(A, gd, s.X, s.Y, s.Z, a)
		api.anim(from, alongF(path, k))
	end
end

-- the shop's animated back, neck and hand pieces (Mythic and Divine)
--
-- Cute things that move, sold for more gems (the user: "make more animated or fancy accessories that cost more", "lean
-- more towards cute accessories"): a bunch of balloons, a sleepy cloud raining sprinkles and a plush bunny backpack on
-- the back; a scarf with a hamster in it, a candy necklace and a butterfly bow round the neck; a plush puppy, a ribbon
-- wand and a bunny lantern in the hand. They move like the Weekly Cup's (Api.anim on the world's clock); still pictures
-- show the rest pose. Their shared shapes, moves and tables are in TOY (one local: this chunk keeps its locals few).
local TOY = {}

-- a frame on the surface of a ball (middle c, radius r) toward dir: its Z points out of the ball, its Y as near up as it
-- goes (faces, buttons and cheeks on round plush heads)
function TOY.onBall(c: Vector3, r: number, dir: Vector3): CFrame
	local n = dir.Unit
	local p = c + n * r
	return CFrame.lookAt(p, p - n, Vector3.new(0, 1, 0))
end

-- the frames of a part drawn at `rest` (rig space) that stands at at[f] on frame f
function TOY.poseF(rest: CFrame, at: { CFrame }): { CFrame }
	local inv = rest:Inverse()
	local out: { CFrame } = table.create(#at)
	for f, cf in at do
		out[f] = cf * inv
	end
	return out
end

-- a ribbon bow facing F's Z, s across: two round loops pinched to a knot (in `knot`), two tails flaring out under it
function TOY.bow(api: Api, bone: number, F: CFrame, s: number, t: number, color: string, knot: string)
	for _, sx in { -1, 1 } do
		fdisc(api, bone, F, s * 0.46, t, sx * s * 0.27, s * 0.04, 0, color)
		fput(api, bone, F, s * 0.3, s * 0.22, t, sx * s * 0.12, s * 0.02, 0, color, ANG(0, 0, sx * 0.3))
		fput(api, bone, F, s * 0.14, s * 0.38, t, sx * s * 0.12, -s * 0.25, 0, color, ANG(0, 0, sx * 0.4))
	end
	fdisc(api, bone, F, s * 0.22, t * 1.4, 0, 0, 0, knot)
end

-- a heart facing F's Z (heart's shape), every piece aglow
function TOY.litHeart(api: Api, bone: number, F: CFrame, s: number, t: number, color: string)
	fdisc(api, bone, F, s * 0.55, t, -s * 0.21, s * 0.09, 0, color)
	api.glow()
	fdisc(api, bone, F, s * 0.55, t, s * 0.21, s * 0.09, 0, color)
	api.glow()
	fput(api, bone, F, s * 0.55, s * 0.55, t, 0, -s * 0.125, 0, color, DIAMOND)
	api.glow()
end

-- Mythic: four balloons floating over and behind the head, their strings curving up from a bow on the back: a little
-- round one in the accent, a round one in the main colour, a heart in the accent and a yellow star, each with a shine.
-- Each bobs and sways about the bow on its own loop and tilts on its string.
TOY.BALLOONS = {
	-- { shape (1 round, 2 heart, 3 star), tone (1 the main colour, 2 the accent, 3 yellow), middle x, y, z, size, the
	--   bob's period and phase, the sway's period and phase, the tilt's period }
	{ 1, 2, -1.46, 4.98, -1.66, 0.74, 8, 2.0, 12, 1.0, 6 },
	{ 1, 1, -0.62, 5.48, -1.56, 0.98, 12, 0, 24, 0, 8 },
	{ 2, 2, 0.46, 5.82, -1.42, 1.02, 8, 1.2, 24, 2.4, 12 },
	{ 3, 3, 1.5, 5.12, -1.52, 0.98, 6, 3.1, 12, 4.2, 8 },
} :: { { number } }
BACK.balloon_bunch = function(api, c, a, _ctx)
	local R = api.ROOT
	local tones = { c, a, "yellow" }
	local knot = Vector3.new(0, 2.05, -0.72)
	local Kn, inv = CFrame.new(knot), CFrame.new(-knot)
	TOY.bow(api, R, CFrame.new(0, 2.05, -0.6) * ANG(0, PI, 0), 0.7, 0.12, a, c)
	for i, b in TOY.BALLOONS do
		local shape, col, d = b[1], tones[b[2]], b[6]
		local p = Vector3.new(b[3], b[4], b[5])
		local F = CFrame.new(p) * FACE_CAM
		-- the string's top: under the round one's knot, the heart's point, the star's lower edge
		local tie = p - Vector3.new(0, if shape == 1 then d * 0.5 + 0.1 elseif shape == 2 then d * 0.58 else d * 0.36, 0)
		local from = api.count()
		local pts = { knot - Vector3.new(0, 0, 0.04), Vector3.new(p.X * 0.18, 2.5, -1.3), Vector3.new(p.X * 0.6, 3.6, p.Z - 0.04), tie }
		for k = 1, 3 do
			local q, r = pts[k], pts[k + 1]
			link(api, R, q.X, q.Y, q.Z, r.X, r.Y, r.Z, 0.09, "white")
		end
		local body = api.count()
		if shape == 1 then
			fball(api, R, F, d, 0, 0, 0, col)
			fball(api, R, F, d * 0.86, 0, d * 0.13, 0, col)
			fball(api, R, F, 0.16, 0, -d * 0.5 - 0.03, 0, col)
			fball(api, R, F, 0.16, -d * 0.2, d * 0.24, d * 0.34, "white")
		elseif shape == 2 then
			heart(api, R, F, d, 0.36, col)
			fball(api, R, F, 0.14, 0, -d * 0.53, 0, col)
			fput(api, R, F, 0.13, 0.13, 0.05, -d * 0.28, d * 0.18, 0.19, "white")
		else
			star(api, R, F, d * 0.32, 0.32, col)
			fball(api, R, F, 0.14, 0, -d * 0.3, 0, col)
			fput(api, R, F, 0.12, 0.12, 0.05, -d * 0.1, d * 0.12, 0.18, "white")
		end
		local tilt = b[11]
		api.anim(body, turnF(CFrame.new(tie), tilt, function(f)
			return 0, 0, osc(f, tilt, 0.12, i)
		end))
		-- the bob (up and down) and the sway (about the bow), on a loop of 24 frames
		local frames: { CFrame } = table.create(24)
		for f = 1, 24 do
			local sway = Kn * ANG(osc(f, b[9], 0.05, b[10] + 1.4), 0, osc(f, b[9], 0.09, b[10])) * inv
			frames[f] = CFrame.new(0, osc(f, b[7], 0.12, b[8]), 0) * sway
		end
		api.anim(from, frames)
	end
end

-- Divine: a little cloud buddy floating over the right shoulder, behind the head and turned to the camera: white puffs,
-- pink ones underneath, a sleepy smiling face (shut eyes, pink cheeks). It bobs gently and rains tiny sprinkles (pink,
-- yellow and blue) that fall and vanish; now and then a little rainbow draws itself in an arch behind it, band by band,
-- and goes; two glints twinkle by it.
TOY.CLOUD = {
	-- { x, y, z, across, tone (1 the main colour, 2 the accent) } in the cloud's frame
	{ 0, 0, 0, 0.95, 1 },
	{ -0.5, -0.1, -0.06, 0.7, 1 },
	{ 0.52, -0.08, -0.06, 0.72, 1 },
	{ -0.24, 0.36, -0.1, 0.62, 1 },
	{ 0.26, 0.3, -0.1, 0.56, 1 },
	{ -0.84, -0.2, -0.12, 0.42, 1 },
	{ 0.86, -0.18, -0.12, 0.44, 1 },
	{ -0.36, -0.42, -0.12, 0.48, 2 },
	{ 0.36, -0.4, -0.12, 0.48, 2 },
	{ 0, -0.46, -0.14, 0.46, 2 },
	{ -0.7, -0.36, -0.16, 0.36, 2 },
	{ 0.72, -0.34, -0.16, 0.36, 2 },
} :: { { number } }
TOY.SPRINKLES = {
	-- { across the cloud's bottom, the frame it rests on, tone (1 the accent, 2 yellow, 3 blue), its turn }
	{ -0.1, 0, 1, 0.5 },
	{ 0.62, 3, 2, -0.6 },
	{ 0.22, 6, 3, 1.1 },
	{ 0.44, 1, 1, -1.2 },
	{ 0.04, 4, 2, 0.2 },
	{ 0.74, 7, 3, 0.9 },
} :: { { number } }
TOY.SPRINKLE_DROP = { 0, 0.2, 0.42, 0.66, 0.92 } -- how far a sprinkle has fallen on each of its five frames
BACK.dream_cloud = function(api, c, a, _ctx)
	local R = api.ROOT
	local k = 0.85
	local K = CFrame.new(1.15, 5.1, -1.32) * ANG(0, 0.5, 0) * ANG(-0.3, 0, 0)
	local mid = K.Position
	local from = api.count()
	for _, p in TOY.CLOUD do
		fball(api, R, K, p[4] * k, p[1] * k, p[2] * k, p[3] * k, if p[5] == 1 then c else a)
	end
	-- the face on the middle puff: shut eyes (little smiling arcs), a smile, pink cheeks
	for _, sx in { -1, 1 } do
		fput(api, R, K, 0.12, 0.055, 0.06, sx * 0.17 - 0.04, 0.05, 0.375, "ink", ANG(0, 0, -0.45))
		fput(api, R, K, 0.12, 0.055, 0.06, sx * 0.17 + 0.04, 0.05, 0.375, "ink", ANG(0, 0, 0.45))
		fput(api, R, K, 0.09, 0.05, 0.05, sx * 0.03, -0.09, 0.4, "ink", ANG(0, 0, sx * 0.5))
		fdisc(api, R, K, 0.13, 0.04, sx * 0.28, -0.04, 0.3, a)
	end
	-- the rainbow behind it, three bands of seven pieces; each piece shows from its turn (left to right over four
	-- frames) until its band goes (the inner band first), out of sight in the middle puff the rest of the 32 frames
	local Kr = K * CFrame.new(-0.04, 0.1, -0.24)
	local bands = { a, "yellow", "sky_day" }
	for b, col in bands do
		local r = 1.04 - 0.12 * b
		local n = 7
		local len = 2 * r * math.tan(PI / (2 * n)) + 0.04
		for j = 0, n - 1 do
			local ang = PI - (j + 0.5) * PI / n
			local S = Kr * CFrame.new(cos(ang) * r, sin(ang) * r, 0) * ANG(0, 0, ang + PI / 2)
			local on: { [number]: boolean } = {}
			for f = 2 + math.floor(j * 4 / n), 14 - b do
				on[f] = true
			end
			local p0 = api.count()
			api.add(R, len, 0.12, 0.08, S.X, S.Y, S.Z, col, S.Rotation)
			api.anim(p0, REWARD.onlyF(32, S.Position, mid, on))
		end
	end
	api.anim(from, moveF(16, function(f)
		return Vector3.new(0, osc(f, 16, 0.09), 0)
	end))
	-- the sprinkles: five frames falling from under the cloud, three out of sight in its middle puff
	local tones = { a, "yellow", "blue" }
	for _, s in TOY.SPRINKLES do
		local s0 = (K * CFrame.new(s[1] * k, -0.45, 0.05)).Position
		local path: { Vector3 } = table.create(8)
		for f = 1, 8 do
			path[f] = if f <= 5 then s0 - Vector3.new(0, TOY.SPRINKLE_DROP[f], 0) else mid
		end
		local p0 = api.count()
		fput(api, R, CFrame.new(path[s[2] + 1]) * FACE_CAM, 0.1, 0.22, 0.1, 0, 0, 0, tones[s[3]], ANG(0, 0, s[4]))
		api.anim(p0, alongF(path, s[2]))
	end
	local g1 = (K * CFrame.new(-0.78, 0.5, 0.2)).Position
	local g2 = (K * CFrame.new(0.66, 0.58, 0.15)).Position
	glint(api, R, g1.X, g1.Y, g1.Z, 0.34, HIDE_ROOT, "1210000000000000")
	glint(api, R, g2.X, g2.Y, g2.Z, 0.3, HIDE_ROOT, "0000000012100000")
end

-- Mythic: a plush bunny on the back: a round cream head for a pack, looking out behind, with button eyes (a white
-- glint), a pink nose over a little mouth, pink cheeks, paws at its sides and feet with pink pads; pink straps; long
-- floppy ears (pink inside), one up and out over the right shoulder with a pink bow, the other up behind the head, its
-- tip over it. The ears wave about their roots and flop at the tips, each on its own loops; the nose twitches.
TOY.NOSE_TWITCH = { 0, 0, 0, 0, 0, 0, 0.05, 0, 0.05, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0.05, 0, 0, 0, 0 }
TOY.BUNNY_EARS = {
	-- { side, lean out (radians), length, the tip's bend further out, the tip's length, the wave's period and phase, the
	--   flop's period and phase }: the right one flopped out over the shoulder, the left one up behind the head
	{ 1, 0.44, 1.4, 0.45, 0.85, 12, 0, 6, 1.2 },
	{ -1, 0.12, 1.75, 0.45, 0.8, 16, 2.1, 8, 0.4 },
} :: { { number } }
BACK.bunny_backpack = function(api, c, a, _ctx)
	local R = api.ROOT
	local P, r = Vector3.new(0, 1.82, -1.08), 0.7
	api.ball(R, 2 * r, P.X, P.Y, P.Z, c)
	for _, sx in { -1, 1 } do
		local ft = Vector3.new(sx * 0.32, 1.2, -1.5)
		api.ball(R, 0.4, ft.X, ft.Y, ft.Z, c)
		fdisc(api, R, TOY.onBall(ft, 0.2, Vector3.new(0, -0.2, -1)), 0.22, 0.04, 0, 0, 0, a)
		api.ball(R, 0.34, sx * 0.64, 1.55, -1.32, c)
		local E = TOY.onBall(P, r, Vector3.new(sx * 0.42, 0.22, -1))
		fdisc(api, R, E, 0.25, 0.06, 0, 0, 0.01, "black")
		fput(api, R, E, 0.08, 0.08, 0.04, 0.05, 0.05, 0.05, "white")
		fdisc(api, R, TOY.onBall(P, r, Vector3.new(sx * 0.78, -0.12, -1)), 0.24, 0.04, 0, 0, 0, a)
	end
	-- the nose and mouth, twitching now and then
	local nose = api.count()
	fball(api, R, TOY.onBall(P, r, Vector3.new(0, -0.08, -1)), 0.2, 0, 0, 0, a)
	local Mo = TOY.onBall(P, r, Vector3.new(0, -0.3, -1))
	for _, sx in { -1, 1 } do
		fput(api, R, Mo, 0.13, 0.05, 0.04, sx * 0.055, 0, 0.01, "ink", ANG(0, 0, sx * 0.5))
	end
	api.anim(nose, moveF(24, function(f)
		return Vector3.new(0, TOY.NOSE_TWITCH[f], 0)
	end))
	-- the ears: a long piece up from the top of the head, a floppy tip bent further out, pink inside on both faces
	for _, e in TOY.BUNNY_EARS do
		local sx, len, tip = e[1], e[3], e[5]
		local E0 = CFrame.new(sx * 0.28, 2.36, -1.4) * ANG(-0.12, 0, -sx * e[2])
		local ear = api.count()
		fput(api, R, E0, 0.44, len, 0.14, 0, len / 2, 0, c)
		for _, z in { -0.075, 0.075 } do
			fput(api, R, E0, 0.24, len - 0.25, 0.04, 0, len / 2 + 0.06, z, a)
		end
		local J = E0 * CFrame.new(0, len, 0)
		fdisc(api, R, J, 0.44, 0.14, 0, 0, 0, c)
		if sx > 0 then
			TOY.bow(api, R, E0 * CFrame.new(0, 0.25, -0.1) * ANG(0, PI, 0), 0.42, 0.08, a, c)
		end
		local flop = api.count()
		local E1 = J * ANG(0, 0, -sx * e[4])
		fput(api, R, E1, 0.44, tip, 0.14, 0, tip / 2, 0, c)
		for _, z in { -0.075, 0.075 } do
			fput(api, R, E1, 0.24, tip - 0.1, 0.04, 0, tip / 2, z, a)
		end
		fdisc(api, R, E1, 0.44, 0.14, 0, tip, 0, c)
		api.anim(flop, turnF(J, e[8], function(f)
			return 0, 0, -sx * osc(f, e[8], 0.3, e[9])
		end))
		api.anim(ear, turnF(E0, e[6], function(f)
			return 0, 0, -sx * osc(f, e[6], 0.1, e[7])
		end))
	end
	straps(api, a)
end

-- Divine: a cosy knitted scarf with white stripes round the neck, rolled into a fold under the chin, its two ends
-- hanging down the chest with a fringe. A round hamster (cream cheeks, pink ears, nose and paws, black bead eyes) lives
-- in the fold: it peeks out, pops up, looks round, nibbles a seed (three bites), sends up a little heart and ducks back
-- in (out of sight inside the torso); the scarf's ends sway.
TOY.HAM_AT = { 0, 0, 0, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 0, 0, 0, 0 } -- 0 inside, 1 peeking, 2 up
TOY.HAM_LOOK = { 0, 0, 0, 0, 0, 0.5, 0.5, -0.5, -0.5, 0, 0, 0, 0, 0, 0, 0, 0, -0.3, 0, 0, 0, 0, 0, 0 } -- radians
TOY.HAM_BITE = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
NECK.hamster_scarf = function(api, c, a, _ctx)
	local R = api.ROOT
	-- the wrap, striped, and the fold under the chin: a roll of scarf, striped, joined to the wrap
	api.add(R, 1.78, 0.42, 1.42, 0, 2.38, -0.02, c)
	for _, y in { 2.28, 2.46 } do
		api.add(R, 1.8, 0.07, 1.44, 0, y, -0.02, "white")
	end
	api.add(R, 0.72, 0.56, 0.42, 0.05, 2.02, 0.86, c)
	api.add(R, 0.86, 0.54, 0.54, 0.05, 1.86, 1.18, c, nil, "Cylinder")
	for _, x in { -0.19, 0.29 } do
		api.add(R, 0.08, 0.56, 0.56, x, 1.86, 1.18, "white", nil, "Cylinder")
	end
	-- the ends from behind the fold: { x, y, z, length, lean, the sway's phase }
	for _, e in { { -0.2, 1.42, 0.88, 0.74, -0.08, 0 }, { 0.28, 1.36, 0.9, 0.62, 0.12, 2.2 } } do
		local F = CFrame.new(e[1], e[2], e[3]) * ANG(0.12, 0, e[5])
		local L = e[4]
		local from = api.count()
		fput(api, R, F, 0.4, L, 0.15, 0, 0, 0, c)
		for _, y in { 0.12, -0.1 } do
			fput(api, R, F, 0.42, 0.07, 0.17, 0, y, 0, "white")
		end
		for _, x in { -0.13, 0, 0.13 } do
			fput(api, R, F, 0.08, 0.14, 0.12, x, -L / 2 - 0.06, 0, c)
		end
		api.anim(from, turnF(F * CFrame.new(0, L / 2, 0), 12, function(f)
			return osc(f, 12, 0.05, e[6] + 1), 0, osc(f, 12, 0.07, e[6])
		end))
	end
	-- the hamster, drawn popped up, turned a little to the camera
	local Hc = CFrame.new(0.05, 2.14, 1.12)
	local Hm = Hc * ANG(0, 0.35, 0)
	local ham = api.count()
	fball(api, R, Hm, 0.58, 0, 0, 0, a)
	fball(api, R, Hm, 0.38, 0, -0.075, 0.13, "cream")
	for _, sx in { -1, 1 } do
		fball(api, R, Hm, 0.24, sx * 0.15, -0.065, 0.11, "cream")
		fball(api, R, Hm, 0.11, sx * 0.11, 0.08, 0.24, "black")
		fput(api, R, Hm, 0.05, 0.05, 0.03, sx * 0.11 + 0.027, 0.105, 0.29, "white")
		fball(api, R, Hm, 0.17, sx * 0.16, 0.25, -0.02, a)
		fdisc(api, R, Hm, 0.11, 0.04, sx * 0.16, 0.26, 0.065, "pink")
	end
	fball(api, R, Hm, 0.09, 0, -0.01, 0.32, "pink")
	-- its paws holding a seed, lifted to its mouth on each bite
	local paws = api.count()
	for _, sx in { -1, 1 } do
		fball(api, R, Hm, 0.11, sx * 0.075, -0.16, 0.27, "pink")
	end
	fput(api, R, Hm, 0.08, 0.13, 0.06, 0, -0.13, 0.32, "chocolate")
	api.anim(paws, moveF(24, function(f)
		return Vector3.new(0, 0.07 * TOY.HAM_BITE[f], 0)
	end))
	local hide = CFrame.new(0, -0.39, -0.92)
	local inv = Hc:Inverse()
	local out: { CFrame } = table.create(24)
	for f = 1, 24 do
		local at = TOY.HAM_AT[f]
		local turn = Hc * ANG(0.15 * TOY.HAM_BITE[f], TOY.HAM_LOOK[f], 0) * inv
		out[f] = if at == 0 then hide elseif at == 1 then CFrame.new(0, -0.1, 0) * turn else turn
	end
	api.anim(ham, out)
	-- the heart it sends up after its meal (out of sight in the torso the rest of the loop)
	local h0 = api.count()
	heart(api, R, CFrame.new(HIDE_ROOT) * FACE_CAM, 0.24, 0.07, "pink")
	api.anim(h0, REWARD.showF(24, HIDE_ROOT, { [16] = Vector3.new(0.38, 2.36, 1.28), [17] = Vector3.new(0.44, 2.54, 1.3), [18] = Vector3.new(0.5, 2.72, 1.32) }))
end

-- Mythic: a candy necklace: round candy beads in five pastel colours (pink, the accent, yellow, sky blue, purple),
-- each with a shine, on a white cord dipping low on the chest, and a wrapped sweet hanging in front (pink with white stripes, its twisted ends in the
-- accent). A glint runs along the beads from shoulder to shoulder, and the sweet swings.
NECK.candy_necklace = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.62, 0.08, 1.12, 0, 2.43, 0, "white")
	local tones = { c, a, "yellow", "sky_day", "purple" }
	local cam = Vector3.new(0.61, 0.5, 0.61).Unit
	local path: { Vector3 } = {}
	for k = 0, 10 do
		local u = -1 + k / 5
		local p = Vector3.new(0.66 * u, 1.8 + 0.6 * u * u, 0.5 + 0.34 * math.sqrt(1 - u * u))
		api.ball(R, 0.3, p.X, p.Y, p.Z, tones[k % 5 + 1])
		api.add(R, 0.08, 0.08, 0.05, p.X - 0.05, p.Y + 0.07, p.Z + 0.13, "white")
		if k >= 1 and k <= 9 then
			table.insert(path, p + cam * 0.17)
		end
	end
	-- the glint: a bead a frame across the front, then three frames out of sight in the torso
	for _ = 1, 3 do
		table.insert(path, HIDE_ROOT)
	end
	local g = api.count()
	sparkle(api, R, CFrame.new(path[1]) * FACE_CAM, 0.34, "white")
	api.anim(g, alongF(path, 0))
	-- the sweet on a ring under the middle bead, turned to the camera, swinging
	local Rg = CFrame.new(0, 1.6, 0.88) * ANG(0, 0.45, 0)
	local from = api.count()
	fball(api, R, Rg, 0.11, 0, 0, 0, "white")
	local Cd = Rg * CFrame.new(0, -0.29, 0.03)
	fball(api, R, Cd, 0.42, 0, 0, 0, c)
	for _, sx in { -1, 1 } do
		fput(api, R, Cd, 0.08, 0.43, 0.43, sx * 0.09, 0, 0, "white", nil, "Cylinder")
		fball(api, R, Cd, 0.12, sx * 0.23, 0, 0, a)
		spike(api, R, Cd * CFrame.new(sx * 0.38, 0, 0) * ANG(0, 0, sx * PI / 2), 0.36, 0.25, 0.09, 0, 0, 0, a)
	end
	api.anim(from, turnF(Rg, 8, function(f)
		return 0, 0, osc(f, 8, 0.3)
	end))
end

-- Mythic: a bow at the collar shaped like a butterfly: round wings (big upper ones, smaller lower ones) with spots in
-- the accent and a white dot, a black body with antennae tipped in the accent, two ribbon tails under it, a band round
-- the neck. The wings flap; now and then a tiny butterfly in the accent flutters off the chest, round a loop and back.
TOY.FLAP = { 0, 0.4, 0.85, 1.05, 0.85, 0.4, 0, -0.12 } -- the wings' turn toward the front (radians) over 8 frames
TOY.FLUTTER = {
	-- the tiny butterfly's way from where it rests, over 16 frames
	{ 0, 0, 0 },
	{ 0, 0, 0 },
	{ 0, 0, 0 },
	{ 0, 0, 0 },
	{ 0, 0, 0 },
	{ 0.18, 0.14, 0.12 },
	{ 0.42, 0.34, 0.26 },
	{ 0.7, 0.46, 0.36 },
	{ 0.9, 0.36, 0.42 },
	{ 0.92, 0.12, 0.4 },
	{ 0.74, -0.04, 0.32 },
	{ 0.48, -0.06, 0.2 },
	{ 0.24, 0.02, 0.1 },
	{ 0.08, 0.04, 0.03 },
	{ 0, 0, 0 },
	{ 0, 0, 0 },
} :: { { number } }
NECK.butterfly_bow = function(api, c, a, _ctx)
	local R = api.ROOT
	api.add(R, 1.62, 0.12, 1.12, 0, 2.42, 0, c)
	local B = CFrame.new(0, 1.94, 0.92) * ANG(0, 0.3, 0)
	local s = 1.15
	for _, sx in { -1, 1 } do
		fput(api, R, B, 0.13, 0.38, 0.06, sx * 0.1, -0.31, -0.07, c, ANG(0, 0, sx * 0.35))
	end
	-- the wings, hinged on the body
	for _, sx in { -1, 1 } do
		local from = api.count()
		fdisc(api, R, B, 0.42 * s, 0.07, sx * 0.24 * s, 0.1 * s, 0, c)
		fdisc(api, R, B, 0.3 * s, 0.07, sx * 0.38 * s, 0.22 * s, 0, c)
		fdisc(api, R, B, 0.3 * s, 0.07, sx * 0.19 * s, -0.15 * s, 0, c)
		fdisc(api, R, B, 0.15 * s, 0.05, sx * 0.3 * s, 0.15 * s, 0.045, a)
		fdisc(api, R, B, 0.1 * s, 0.05, sx * 0.2 * s, -0.17 * s, 0.045, a)
		fdisc(api, R, B, 0.08, 0.05, sx * 0.45 * s, 0.29 * s, 0.045, "white")
		api.anim(from, turnF(B, 8, function(f)
			return 0, -sx * TOY.FLAP[f], 0
		end))
	end
	-- the body, its head and antennae
	fput(api, R, B, 0.11, 0.34, 0.12, 0, -0.02, 0.06, "black")
	fball(api, R, B, 0.13, 0, -0.18, 0.06, "black")
	fball(api, R, B, 0.17, 0, 0.2, 0.06, "black")
	for _, sx in { -1, 1 } do
		local p = B:PointToWorldSpace(Vector3.new(sx * 0.04, 0.27, 0.06))
		local q = B:PointToWorldSpace(Vector3.new(sx * 0.15, 0.45, 0.06))
		link(api, R, p.X, p.Y, p.Z, q.X, q.Y, q.Z, 0.05, "black")
		api.ball(R, 0.09, q.X, q.Y, q.Z, a)
	end
	-- the tiny butterfly, resting on the chest, its wings beating every frame
	local p0 = Vector3.new(0.5, 1.72, 0.78)
	local path: { Vector3 } = {}
	for f, o in TOY.FLUTTER do
		path[f] = p0 + Vector3.new(o[1], o[2], o[3])
	end
	local S = CFrame.new(p0) * FACE_CAM
	local fly = api.count()
	fput(api, R, S, 0.06, 0.16, 0.06, 0, 0, 0.02, "black")
	for _, sx in { -1, 1 } do
		local w = api.count()
		fdisc(api, R, S, 0.17, 0.04, sx * 0.09, 0.04, 0, a)
		fdisc(api, R, S, 0.12, 0.04, sx * 0.07, -0.06, 0, a)
		api.anim(w, turnF(S, 2, function(f)
			return 0, if f == 1 then 0 else -sx * 1.0, 0
		end))
	end
	api.anim(fly, alongF(path, 0))
end

-- Divine: a plush puppy sitting on the fist, facing the camera: a big round cream head and a body with a white chest
-- and muzzle, floppy chocolate ears, a chocolate patch round one eye and a spot on its back, a black nose, black eyes
-- with a glint, a pink tongue, a red collar with a gold tag, paws and a tail. The tail wags fast, the ears flop, each on
-- its own loop, and now and then it tilts its head and a little heart floats up.
TOY.PUP_TILT = { 0, 0, 0, 0, 0, 0, 0, 0, 0.14, 0.3, 0.3, 0.3, 0.3, 0.14, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 } -- radians
TOY.PUP_EARS = { { -1, 8, 0 }, { 1, 12, 1.7 } } :: { { number } } -- { side, the flop's period and phase }
HAND.puppy_plush = function(api, c, a, _ctx)
	local A = api.ARM_R
	local F = CFrame.new(1.04, 1.22, 0.64) * ANG(0, 0.55, 0)
	-- drawn a tenth over the size of its numbers
	local s = 1.1
	local function ball(Fr: CFrame, d: number, x: number, y: number, z: number, col: string)
		fball(api, A, Fr, d * s, x * s, y * s, z * s, col)
	end
	local function box(Fr: CFrame, w: number, h: number, t: number, x: number, y: number, z: number, col: string, rot: CFrame?, shape: string?)
		fput(api, A, Fr, w * s, h * s, t * s, x * s, y * s, z * s, col, rot, shape)
	end
	-- the body: a white chest, a spot, hind feet and front paws
	ball(F, 0.6, 0, 0.3, -0.02, c)
	ball(F, 0.34, 0, 0.26, 0.18, "white")
	ball(F, 0.3, 0.2, 0.42, -0.14, a)
	for _, sx in { -1, 1 } do
		ball(F, 0.22, sx * 0.21, 0.07, 0.1, c)
		ball(F, 0.17, sx * 0.1, 0.06, 0.26, c)
	end
	-- the tail, wagging a beat a frame
	local T = F * CFrame.new(0, 0.24 * s, -0.28 * s) * ANG(-0.7, 0, 0)
	local tail = api.count()
	box(T, 0.13, 0.3, 0.13, 0, 0.13, 0, c)
	ball(T, 0.16, 0, 0.28, 0, a)
	api.anim(tail, turnF(T, 2, function(f)
		return 0, 0, if f == 1 then 0.55 else -0.55
	end))
	-- the collar and its tag
	fcyl(api, A, F, 0.44 * s, 0.1 * s, 0.56 * s, "berry_red")
	box(F, 0.05, 0.13, 0.13, 0, 0.47, 0.22, "gold", FRONT, "Cylinder")
	-- the head: the patch round its eye, muzzle, nose, tongue, eyes and glints
	local head = api.count()
	ball(F, 0.64, 0, 0.84, 0.02, c)
	ball(F, 0.24, 0.15, 0.93, 0.18, a)
	ball(F, 0.3, 0, 0.74, 0.25, "white")
	ball(F, 0.13, 0, 0.8, 0.39, "black")
	box(F, 0.08, 0.07, 0.04, 0, 0.64, 0.37, "pink")
	for _, sx in { -1, 1 } do
		ball(F, 0.12, sx * 0.13, 0.92, 0.27, "black")
		box(F, 0.05, 0.05, 0.04, sx * 0.13 + 0.03, 0.95, 0.33, "white")
	end
	-- the ears, hanging from the top of the head, flopping out and back
	for _, e in TOY.PUP_EARS do
		local sx, n = e[1], e[2]
		local E = F * CFrame.new(sx * 0.27 * s, 1.0 * s, 0)
		local ear = api.count()
		box(E, 0.12, 0.38, 0.26, sx * 0.04, -0.19, 0.02, a, ANG(0, 0, sx * 0.15))
		box(E, 0.12, 0.26, 0.26, sx * 0.08, -0.36, 0.02, a, nil, "Cylinder")
		api.anim(ear, turnF(E, n, function(f)
			return 0, 0, sx * (0.12 + osc(f, n, 0.22, e[3]))
		end))
	end
	api.anim(head, turnF(F * CFrame.new(0, 0.56 * s, 0), 24, function(f)
		return 0, 0, TOY.PUP_TILT[f]
	end))
	-- the heart floating up as it tilts its head (out of sight in the arm the rest of the loop)
	local h0 = api.count()
	heart(api, A, CFrame.new(HIDE_ARM) * FACE_CAM, 0.22, 0.07, "pink")
	local hp = (F * CFrame.new(-0.4, 1.36, 0.1)).Position
	api.anim(h0, REWARD.showF(24, HIDE_ARM, { [11] = hp, [12] = hp + Vector3.new(0, 0.17, 0), [13] = hp + Vector3.new(0.02, 0.34, 0) }))
end

-- the ribbon wand's ribbon on frame f of 8, in the plane facing the camera (x across the screen, y up), from the stick's
-- tip at the origin: a loop that grows along the ribbon as it drifts out and down, turning once a loop, so its curls
-- run along it; sampled at equal steps along the ribbon (TOY.RIBBON_N pieces TOY.RIBBON_STEP long)
TOY.RIBBON_N, TOY.RIBBON_STEP = 14, 0.23
function TOY.ribbon(f: number): { Vector3 }
	local dx, dy = cos(-0.85), sin(-0.85)
	local pts: { Vector3 } = { Vector3.zero }
	local prev = Vector3.zero
	local run, u = 0, 0
	while #pts <= TOY.RIBBON_N and u < 30 do
		u += 0.02
		local r = 0.5 * math.min(1, u / 4)
		local ph = u - 2 * PI * (f - 1) / 8
		local q = Vector3.new(dx * 0.22 * u - r * (dx * sin(ph) + dy * cos(ph)), dy * 0.22 * u + r * (dx * cos(ph) - dy * sin(ph)), 0)
		run += (q - prev).Magnitude
		prev = q
		if run >= TOY.RIBBON_STEP then
			table.insert(pts, q)
			run = 0
		end
	end
	return pts
end

-- Mythic: a rhythmic gymnast's ribbon wand held up and out: a stick in the accent with a grip in the main colour and a
-- glowing star at its tip, a long ribbon in the main colour striped in the accent swirling from the star in loops. The
-- ribbon is fourteen pieces, each on its own path round the loop's turn (a piece further along a beat later), turning
-- over as they go; a glint twinkles by the star.
HAND.ribbon_wand = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = GRIP_OUT
	fcyl(api, A, G, 0.12, 1.5, 0.62, a)
	fcyl(api, A, G, 0.17, 0.42, 0.02, c)
	fball(api, A, G, 0.19, 0, -0.22, 0, c)
	local tip = (G * CFrame.new(0, 1.42, 0)).Position
	local T0 = CFrame.new(tip) * CAM_SQ
	-- the ribbon: each piece's place on each frame, drawn where it is on the first
	local frames: { { Vector3 } } = {}
	for f = 1, 8 do
		frames[f] = TOY.ribbon(f)
	end
	for k = 1, TOY.RIBBON_N do
		local at: { CFrame } = table.create(8)
		for f = 1, 8 do
			local p, q = frames[f][k], frames[f][k + 1] or frames[f][k]
			local m = (p + q) / 2
			local twist = 0.5 * sin(2 * PI * (f - 1) / 8 + k * 0.9)
			at[f] = T0 * CFrame.new(m.X, m.Y, -0.012 * k) * ANG(0, 0, math.atan2(q.Y - p.Y, q.X - p.X)) * ANG(twist, 0, 0)
		end
		local rest = at[1]
		local from = api.count()
		api.add(A, TOY.RIBBON_STEP + 0.07, 0.22, 0.06, rest.X, rest.Y, rest.Z, if k % 3 == 0 then a else c, rest.Rotation)
		api.anim(from, TOY.poseF(rest, at))
	end
	star(api, A, T0 * CFrame.new(0, 0.04, 0.05), 0.14, 0.09, a, "white", true)
	local g = (T0 * CFrame.new(-0.36, 0.3, 0.1)).Position
	glint(api, A, g.X, g.Y, g.Z, 0.3, HIDE_ARM, "00012000")
end

-- Mythic: a paper lantern shaped like a sitting bunny, hanging by a pink cord from a short wooden stick held out: a
-- round white paper body banded round, the yellow light inside glowing between the bands and through a heart on its
-- belly, a round head with a little face (pink nose and cheeks), long ears pink inside, feet, a tail, a pink cap and
-- tassel under it. It sways on its cord, and its light flickers softly (now and then the glow dims to a warmer yellow).
TOY.LANTERN_DIM = { 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1, 0 }
HAND.bunny_lantern = function(api, c, a, _ctx)
	local A = api.ARM_R
	-- the stick, out to the side so the lantern hangs clear of the wearer
	local base, top = Vector3.new(1.0, 1.1, 0.1), Vector3.new(2.05, 2.45, -0.05)
	link(api, A, base.X, base.Y, base.Z, top.X, top.Y, top.Z, 0.11, "wood")
	api.ball(A, 0.16, top.X, top.Y, top.Z, a)
	local hang = top - Vector3.new(0, 0.3, 0)
	local L = CFrame.new(hang - Vector3.new(0, 0.86, 0)) * FACE_CAM
	local from = api.count()
	link(api, A, top.X, top.Y - 0.04, top.Z, hang.X, hang.Y, hang.Z, 0.06, a)
	-- the body: the light inside, white bands round it, the caps; the heart on the belly
	fball(api, A, L, 0.7, 0, 0, 0, "yellow")
	api.glow()
	for _, y in { -0.2, 0, 0.2 } do
		fcyl(api, A, L, if y == 0 then 0.76 else 0.66, 0.14, y, c)
	end
	fcyl(api, A, L, 0.4, 0.08, -0.31, a)
	fcyl(api, A, L, 0.4, 0.08, 0.31, c)
	TOY.litHeart(api, A, L * CFrame.new(0, -0.02, 0.37), 0.3, 0.05, "yellow")
	-- the dim light: rings in the gaps and a heart over the belly's, out of sight inside the lantern but on its dim frames
	local Lz = L:VectorToWorldSpace(Vector3.new(0, 0, 0.29))
	for _, sy in { -1, 1 } do
		local d0 = api.count()
		fcyl(api, A, L, 0.72, 0.06, 0, "sponge")
		api.glow()
		api.anim(d0, moveF(12, function(f)
			return Vector3.new(0, if TOY.LANTERN_DIM[f] == 1 then sy * 0.1 else 0, 0)
		end))
	end
	local h0 = api.count()
	TOY.litHeart(api, A, L * CFrame.new(0, -0.02, 0.1), 0.3, 0.05, "sponge")
	api.anim(h0, moveF(12, function(f)
		return if TOY.LANTERN_DIM[f] == 1 then Lz else Vector3.zero
	end))
	-- the head and its face, the ears, feet, tail, the tassel and the ring the cord is tied to
	fball(api, A, L, 0.5, 0, 0.56, 0, c)
	for _, sx in { -1, 1 } do
		fball(api, A, L, 0.08, sx * 0.1, 0.6, 0.21, "ink")
		fdisc(api, A, L, 0.09, 0.03, sx * 0.15, 0.51, 0.19, a)
		fball(api, A, L, 0.18, sx * 0.15, -0.33, 0.2, c)
		local E = L * CFrame.new(sx * 0.11, 0.74, 0) * ANG(0, 0, -sx * 0.18)
		fput(api, A, E, 0.15, 0.46, 0.08, 0, 0.2, 0, c)
		fput(api, A, E, 0.07, 0.32, 0.04, 0, 0.2, 0.05, a)
		fdisc(api, A, E, 0.15, 0.08, 0, 0.43, 0, c)
	end
	fball(api, A, L, 0.07, 0, 0.53, 0.245, a)
	fball(api, A, L, 0.2, 0, -0.12, -0.36, c)
	fput(api, A, L, 0.08, 0.24, 0.08, 0, -0.5, 0, a)
	fball(api, A, L, 0.12, 0, -0.4, 0, a)
	fball(api, A, L, 0.1, 0, 0.83, 0, a)
	api.anim(from, turnF(CFrame.new(top), 12, function(f)
		return osc(f, 12, 0.06, 1.3), 0, osc(f, 12, 0.16)
	end))
	local g = (L * CFrame.new(0.5, 0.25, 0.2)).Position
	glint(api, A, g.X, g.Y, g.Z, 0.28, HIDE_ARM, "000001200000")
end

------------------------------------------------------------------ Halloween part 2: the Costume Rack and the Soulflame

-- The Costume Rack's tier 5 pieces (the bakery's Halloween event: Data/Cosmetics options with `limited = "halloween"` and a
-- `kind`) and the Soulflame Lollipop's own reward, the Soulflame Halo (16.2). The user: "it also gives the player who
-- rolled it a themed animated cosmetic accessory", then "apply the idea for more items in the halloween costume rack".
-- They move like the shop's (Api.anim on the world's clock); still pictures show the rest pose. Their shared shapes,
-- moves and tables are in SPOOK (one local: this chunk keeps its locals few).
local SPOOK = {}

-- a little jack-o'-lantern facing F's Z, d across: a squat pumpkin of three lobes (in `body`), a stem and a leaf (in
-- `stem`), a carved face (two diamond eyes, a grin turned up at its corners) in `carve`. With `pat` the face is lit
-- from inside (aglow) and a dimmer copy of it (in `dim`) sits just inside the pumpkin: on the frames `pat` marks "0" the
-- lit face sinks into the pumpkin and the dim one shows, the candle flickering.
function SPOOK.jack(api: Api, bone: number, F: CFrame, d: number, body: string, stem: string, carve: string, pat: string?, dim: string?)
	fball(api, bone, F, d * 0.8, 0, 0, 0, body)
	for _, sx in { -1, 1 } do
		fball(api, bone, F, d * 0.68, sx * d * 0.24, -d * 0.04, -d * 0.06, body)
	end
	fput(api, bone, F, d * 0.14, d * 0.24, d * 0.14, d * 0.02, d * 0.45, -d * 0.02, stem, ANG(0, 0, -0.3))
	fput(api, bone, F, d * 0.24, d * 0.08, d * 0.14, d * 0.17, d * 0.42, 0, stem, ANG(0, 0.4, -0.45))
	local lit = pat ~= nil
	-- (the dim face, hidden but for a flicker, without the grin's corners)
	local function face(col: string, z: number, s: number, corners: boolean)
		for _, sx in { -1, 1 } do
			fput(api, bone, F, d * 0.2 * s, d * 0.2 * s, 0.06, sx * d * 0.16, d * 0.09, z, col, DIAMOND)
			if lit then
				api.glow()
			end
			if corners then
				fput(api, bone, F, d * 0.11 * s, d * 0.12 * s, 0.06, sx * d * 0.19, -d * 0.1, z - 0.01, col)
				if lit then
					api.glow()
				end
			end
		end
		fput(api, bone, F, d * 0.36 * s, d * 0.11 * s, 0.06, 0, -d * 0.16, z - 0.01, col)
		if lit then
			api.glow()
		end
	end
	if pat and dim then
		face(dim, d * 0.37 - 0.03, 0.9, false)
		local from = api.count()
		face(carve, d * 0.37, 1, true)
		local back = F:VectorToWorldSpace(Vector3.new(0, 0, -0.14))
		api.anim(from, moveF(#pat, function(f)
			return if string.sub(pat, f, f) == "1" then Vector3.zero else back
		end))
	else
		face(carve, d * 0.37, 1, true)
	end
end

-- Floating Jack-o'-Lanterns: three jack-o'-lanterns floating round the head on a ring tipped to the camera, their
-- faces always to it: squat pumpkins (the colour) with a green stem and leaf, faces lit from inside (the accent). They
-- circle the head (a third of a turn a loop, so the pattern repeats), bobbing and rocking as they go, and each candle
-- flickers on its own beat (the face dimming to a warm orange for a frame).
SPOOK.JACK_LIT = { "111101111110", "110111111011", "111111011101" }
HAT.floating_jacks = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local O = CFrame.new(0, t + 0.62, -0.05) * ANG(0.16, 0, 0)
	local function at(ang: number): Vector3
		return (O * CFrame.new(cos(ang) * 1.3, 0.1 * sin(3 * ang), sin(ang) * 1.3)).Position
	end
	for k = 0, 2 do
		local a0 = k * 2 * PI / 3 + PI / 6
		local p = at(a0)
		local from = api.count()
		SPOOK.jack(api, H, CFrame.new(p) * FACE_CAM, 1.05, c, "green", a, SPOOK.JACK_LIT[k + 1], "oven_glow")
		-- the rock goes with the place on the ring (so a loop's end meets its start), then the way round the ring
		local frames: { CFrame } = table.create(12)
		for f = 1, 12 do
			frames[f] = CFrame.new(p) * ANG(0, 0, 0.12 * sin(3 * (a0 - 2 * PI / 3 * (f - 1) / 12) + 1)) * CFrame.new(-p)
		end
		api.anim(from, frames)
		api.anim(from, REWARD.orbitF(12, a0, -2 * PI / 3, at))
	end
end

-- Bubbling Cauldron Hat (bottom 4.3): a little iron cauldron worn as a hat: a round belly (the colour) with an iron
-- hoop, a narrower neck under a thick rim, a ring handle out of each side, and glowing green brew (the accent) filled to
-- the brim and running over it in two drips, a bone poking out of it. Bubbles rise out of the brew, drift and are gone;
-- one swells on its surface and pops; a drop falls off the front drip.
SPOOK.BUBBLES = {
	-- { x, z, across, where it starts along its path (of 8: still pictures show one high over the brew, the others in the
	-- pot, so no two sit side by side on it like a pair of eyes), its wobble's phase }
	{ -0.45, 0.25, 0.4, 2, 0 },
	{ 0.5, -0.2, 0.34, 5, 1.7 },
	{ 0.1, 0.5, 0.3, 7, 3.1 },
	{ -0.2, -0.45, 0.36, 6, 4.4 },
} :: { { number } }
-- the swelling bubble's size on each of 12 frames (0: not there; still pictures show none): it pops on frame 10
SPOOK.SWELL = { 0, 0, 0, 0.3, 0.3, 0.46, 0.46, 0.62, 0.62, 0, 0, 0 }
HAT.cauldron_hat = function(api, c, a, _ctx)
	local H = api.HEAD
	local y0, z0 = 4.3, -0.05
	local top = y0 + 1.0
	api.cyl(H, 2.6, 0.14, 0, y0 + 0.07, z0, c)
	api.cyl(H, 2.9, 0.52, 0, y0 + 0.4, z0, c)
	api.cyl(H, 3.0, 0.1, 0, y0 + 0.5, z0, "street")
	api.cyl(H, 2.5, 0.22, 0, y0 + 0.76, z0, c)
	api.cyl(H, 2.7, 0.16, 0, top - 0.08, z0, c)
	api.cyl(H, 2.34, 0.06, 0, top + 0.02, z0, a)
	api.glow()
	-- a bone poking out of the brew
	local Bn = CFrame.new(-0.45, top + 0.38, z0 - 0.25) * ANG(0.2, 0, 0.38)
	fput(api, H, Bn, 0.16, 0.8, 0.16, 0, 0, 0, "white")
	for _, sx in { -1, 1 } do
		fball(api, H, Bn, 0.24, sx * 0.09, 0.42, 0, "white")
	end
	-- the handles: a ring out of each side (the inner side against the pot)
	for _, sx in { -1, 1 } do
		api.add(H, 0.46, 0.1, 0.12, sx * 1.46, y0 + 0.88, z0, c)
		api.add(H, 0.3, 0.1, 0.12, sx * 1.55, y0 + 0.56, z0, c)
		api.add(H, 0.1, 0.42, 0.12, sx * 1.67, y0 + 0.72, z0, c)
	end
	-- the drips over the rim on the camera's side, down the neck and over the belly
	for _, d in { { 0.95, 0.42 }, { -0.4, 0.3 } } do
		local ang, len = d[1], d[2]
		local dx, dz = sin(ang), cos(ang)
		api.add(H, 0.22, 0.36, 0.2, dx * 1.33, top - 0.2, z0 + dz * 1.33, a, ANG(0, ang, 0))
		api.glow()
		api.ball(H, 0.26, dx * 1.47, top - 0.06 - len, z0 + dz * 1.47, a)
		api.glow()
	end
	-- a drop falling off the front drip
	local dx, dz = sin(0.95) * 1.52, cos(0.95) * 1.52
	local path: { Vector3 } = {}
	for f, dy in { 0.0, -0.08, -0.22, -0.42, -0.68 } do
		path[f] = Vector3.new(dx, top - 0.5 + dy, z0 + dz)
	end
	path[6], path[7], path[8] = HIDE_HEAD, HIDE_HEAD, HIDE_HEAD
	local d0 = api.count()
	api.ball(H, 0.18, path[1].X, path[1].Y, path[1].Z, a)
	api.glow()
	api.anim(d0, alongF(path, 0))
	-- the bubbles: rising out of the brew in a wobble over five frames, inside the pot the other three
	local inside = Vector3.new(0, y0 + 0.5, z0)
	for _, b in SPOOK.BUBBLES do
		local bp: { Vector3 } = {}
		for f = 1, 5 do
			bp[f] = Vector3.new(b[1] + 0.08 * sin(f * 1.4 + b[5]), top + 0.06 + 0.22 * f, z0 + b[2] + 0.05 * cos(f * 1.4 + b[5]))
		end
		bp[6], bp[7], bp[8] = inside, inside, inside
		local k = b[4]
		local b0 = api.count()
		local p0 = bp[k + 1]
		api.ball(H, b[3], p0.X, p0.Y, p0.Z, a)
		api.glow()
		api.anim(b0, alongF(bp, k))
	end
	-- the bubble that swells on the surface (three sizes in turn), then pops in a ring of droplets: drawn in the pot
	-- and brought out on their frames
	local S = Vector3.new(0.4, top + 0.04, z0 + 0.36)
	for _, sz in { 0.3, 0.46, 0.62 } do
		local at: { [number]: Vector3 } = {}
		for f, w in SPOOK.SWELL do
			if w == sz then
				at[f] = S
			end
		end
		local s0 = api.count()
		api.ball(H, sz, inside.X, inside.Y, inside.Z, a)
		api.glow()
		api.anim(s0, REWARD.showF(12, inside, at))
	end
	for k = 0, 2 do
		local ang = k * 2 * PI / 3 + 0.3
		local q = S + Vector3.new(cos(ang) * 0.4, 0.32 + 0.1 * k, sin(ang) * 0.4)
		local q0 = api.count()
		api.ball(H, 0.16, inside.X, inside.Y, inside.Z, a)
		api.glow()
		api.anim(q0, REWARD.showF(12, inside, { [10] = q }))
	end
end

-- Soulflame Halo (the Soulflame Lollipop's reward, never sold; a rainbow piece: its colours are fixed): a ring of soul
-- fire floating over the head, tipped to the camera: a thick glowing soul green ring with a violet rim inside it, eight
-- tongues of flame standing round it (tall green ones and shorter violet ones by turns), each flickering on its own
-- beat. The ring turns slowly and bobs; two wisps (a white-hot head and a curling tail, one green, one violet) circle
-- the head the other way on a wider ring of their own; embers rise off the flames and go; glints twinkle round it.
SPOOK.WISP_TAIL = { 0.28, 0.2, 0.13 } -- across: the balls of a wisp's tail, behind its head
SPOOK.EMBERS = {
	-- { angle round the ring, tone (1 green, 2 violet), where it starts along its path (of 8: the still pictures show
	-- the first two low over the flames, the others out of sight) }
	{ 0.4, 1, 0 },
	{ 2.5, 2, 1 },
	{ 4.0, 1, 5 },
	{ 5.4, 2, 6 },
} :: { { number } }
-- a tongue of soul flame standing at S (its root, Y up), h tall: three blocks narrowing to a tip, each turned corner
-- out; on a loop of four frames the blocks sway and leap (the tip most), `ph` along it
function SPOOK.tongue(api: Api, bone: number, S: CFrame, h: number, color: string, ph: number)
	local BLOCKS = { { 0.42, 0.4, 0.2, 0.03 }, { 0.3, 0.34, 0.5, 0.07 }, { 0.17, 0.3, 0.8, 0.12 } }
	for i, b in BLOCKS do
		local w, hh, at, leap = b[1], b[2] * h, b[3] * h, b[4]
		local from = api.count()
		fput(api, bone, S, w, hh, w, 0, at, 0, color, ANG(0, PI / 4 + 0.2 * i, 0))
		api.glow()
		local up = S:VectorToWorldSpace(Vector3.new(0, 1, 0))
		local side = S:VectorToWorldSpace(Vector3.new(1, 0, 0))
		api.anim(from, moveF(4, function(f)
			local q = (f - 1 + ph) % 4
			return up * (if q == 1 then leap elseif q == 3 then leap * 0.5 else 0) + side * (if q == 1 then -leap elseif q == 2 then leap else 0) * 0.8
		end))
	end
end
HAT.soulflame_halo = function(api, c, a, ctx)
	local H, t = api.HEAD, capTop(ctx)
	local F = CFrame.new(0, t + 0.92, -0.05) * ANG(0.2, 0, 0)
	local R = 1.05
	local from = api.count()
	ring(api, H, F, R, 12, 0.24, 0.3, c, true)
	ring(api, H, F * CFrame.new(0, -0.03, 0), R - 0.2, 8, 0.14, 0.12, a, true)
	for k = 0, 7 do
		local ang = k * PI / 4 + PI / 8
		local S = F * CFrame.new(cos(ang) * R, 0.1, sin(ang) * R)
		if k % 2 == 0 then
			SPOOK.tongue(api, H, S, 0.88, c, k)
		else
			SPOOK.tongue(api, H, S, 0.62, a, k)
		end
	end
	-- the ring turns (a quarter turn a loop: the flames repeat) and bobs
	local inv = F:Inverse()
	local frames: { CFrame } = table.create(16)
	for f = 1, 16 do
		frames[f] = CFrame.new(0, osc(f, 16, 0.07), 0) * F * ANG(0, PI / 2 * (f - 1) / 16, 0) * inv
	end
	api.anim(from, frames)
	-- the wisps, half a turn a loop the other way, their tails behind them; still pictures show them at the front-left
	-- and the back-right, clear of the head
	local O = CFrame.new(0, t + 0.82, -0.05) * ANG(0.2, 0, -0.1)
	for k = 0, 1 do
		local a0 = k * PI + 3 * PI / 4
		local w0 = api.count()
		for i = 0, 3 do
			local ang = a0 - i * 0.22
			local d = if i == 0 then 0.38 else SPOOK.WISP_TAIL[i]
			fball(api, H, O, d, cos(ang) * 1.6, 0.05 * i, sin(ang) * 1.6, if i == 0 then "white" elseif k == 1 then a else c)
			api.glow()
		end
		api.anim(w0, spinF(O, 12, -PI))
	end
	-- embers rising off the flames, out of sight in the head the last three frames of eight
	for _, e in SPOOK.EMBERS do
		local base = (F * CFrame.new(cos(e[1]) * R, 0.55, sin(e[1]) * R)).Position
		local path: { Vector3 } = {}
		for f = 1, 5 do
			path[f] = base + Vector3.new(0.06 * sin(f * 1.3 + e[1]), 0.2 * f, 0.04 * cos(f + e[1]))
		end
		path[6], path[7], path[8] = HIDE_HEAD, HIDE_HEAD, HIDE_HEAD
		local k = e[3]
		local p0 = path[k + 1]
		local e0 = api.count()
		api.add(H, 0.16, 0.16, 0.16, p0.X, p0.Y, p0.Z, if e[2] == 1 then c else a, ANG(PI / 4, PI / 4, 0))
		api.glow()
		api.anim(e0, alongF(path, k))
	end
	glint(api, H, -1.3, t + 1.35, 0.4, 0.42, HIDE_HEAD, "1210000000000000")
	glint(api, H, 1.32, t + 0.8, 0.55, 0.38, HIDE_HEAD, "0000000012100000")
end

-- Glowing Eyes: the eyes lit up in a soul green glow (the colour): a round bright core over each eye (big enough to
-- hide the eye, open or shut in a blink), a white catch-light (the accent), round it a ring of the colour unlit, like the
-- glow's edge; wisps of light trail off their outer corners and drift away. The glow flickers: now and then it flares
-- (a white star across each eye), and twice a loop it gutters out for a frame, the founder's own eyes showing.
SPOOK.EYE_LIT = "111111110101"
FACE.glowing_eyes = function(api, c, a, _ctx)
	local H = api.HEAD
	local back = Vector3.new(0, 0, -0.4)
	for _, sx in { -1, 1 } do
		local x = sx * 0.45
		local lit = api.count()
		disc(api, H, 0.74, 0.04, x, 3.4, 1.13, c)
		disc(api, H, 0.56, 0.06, x, 3.4, 1.16, c)
		api.glow()
		api.add(H, 0.14, 0.2, 0.06, x - sx * 0.08, 3.5, 1.2, a)
		api.glow()
		api.anim(lit, moveF(12, function(f)
			return if string.sub(SPOOK.EYE_LIT, f, f) == "1" then Vector3.zero else back
		end))
		-- the flare: a white star across the eye on one frame of twelve (drawn in the head, so still pictures show none)
		local fl = api.count()
		sparkle(api, H, CFrame.new(HIDE_HEAD), 0.82, a)
		api.anim(fl, REWARD.showF(12, HIDE_HEAD, { [4] = Vector3.new(x, 3.4, 1.24) }))
		-- two wisps trailing off the outer corner, out and up, gone into the head a frame of six
		local path: { Vector3 } = {}
		for f = 1, 5 do
			path[f] = Vector3.new(sx * (0.64 + 0.15 * f), 3.48 + 0.08 * f + 0.03 * sin(f * 1.6), 1.16 - 0.05 * f)
		end
		path[6] = HIDE_HEAD
		for _, k in { 0, 3 } do
			local w0 = api.count()
			local q = path[k + 1]
			api.add(H, if k == 0 then 0.16 else 0.12, 0.12, 0.06, q.X, q.Y, q.Z, c, ANG(0, 0, sx * 0.4))
			api.glow()
			api.anim(w0, alongF(path, k))
		end
	end
end

-- Ghostly Breath: a little round "o" of a mouth breathing out puffs of cold breath (the accent) and little ghosts (the
-- colour: a round head with a tail curling under it, two black eyes) that come out of it small, grow as they drift out
-- to the side one after another (two to the camera's side, one to the other), wobbling, rising, and gone.
SPOOK.GHOSTS = {
	-- { side, where it starts along its path (of 9), across when grown }
	{ 1, 1, 0.6 },
	{ -1, 4, 0.54 },
	{ 1, 7, 0.58 },
} :: { { number } }
-- a little ghost facing F's Z, s across: a round head, a tail of three balls curling down and away behind it (to F's
-- -X, or +X with `fx` -1), two eyes
function SPOOK.ghost(api: Api, bone: number, F: CFrame, s: number, color: string, fx: number)
	fball(api, bone, F, s, 0, 0, 0, color)
	fball(api, bone, F, s * 0.72, -fx * s * 0.12, -s * 0.36, -s * 0.04, color)
	fball(api, bone, F, s * 0.48, -fx * s * 0.34, -s * 0.6, -s * 0.06, color)
	fball(api, bone, F, s * 0.28, -fx * s * 0.58, -s * 0.66, -s * 0.06, color)
	for _, ex in { -1, 1 } do
		fput(api, bone, F, s * 0.18, s * 0.28, 0.06, ex * s * 0.17, s * 0.06, s * 0.49, "ink")
	end
end
FACE.ghost_breath = function(api, c, a, _ctx)
	local H = api.HEAD
	local mx, my = 0.08, 2.86
	disc(api, H, 0.22, 0.06, mx, my, 1.03, "ink")
	-- the breath: a puff as each ghost comes out, a smaller one the frame after
	for i, d in { 0.26, 0.2 } do
		local off = 0.16 * (i - 1)
		local p = Vector3.new(mx + off, my + off * 0.4, 1.14)
		local fr = if i == 1 then 3 else 1
		local p0 = api.count()
		api.ball(H, d, p.X, p.Y, p.Z, a)
		api.anim(p0, REWARD.onlyF(9, p, HIDE_HEAD, { [fr] = true, [fr + 3] = true, [fr + 6] = true }))
	end
	for i, g in SPOOK.GHOSTS do
		local sx, k, s = g[1], g[2], g[3]
		-- its path: out of the mouth sideways, then rising (seven frames), in the head the last two
		local path: { Vector3 } = {}
		for f = 1, 7 do
			local u = f / 7
			path[f] = Vector3.new(mx + sx * (0.15 + 1.35 * u) + 0.06 * sin(f * 1.7 + i), my - 0.04 + 0.9 * u * u * u, 1.2 + 0.2 * u)
		end
		path[8], path[9] = HIDE_HEAD, HIDE_HEAD
		-- small on the first two frames of its path, grown the next five: each drawn where frame 1 has it (else hidden)
		for _, sz in { 1, 2 } do
			local at = (k % 9) + 1
			local function on(idx: number): boolean
				return if sz == 1 then idx <= 2 else idx >= 3 and idx <= 7
			end
			local p0 = if on(at) then path[at] else HIDE_HEAD
			local g0 = api.count()
			SPOOK.ghost(api, H, CFrame.new(p0) * ANG(0, PI / 8, sx * 0.25), if sz == 1 then s * 0.6 else s, c, sx)
			api.anim(g0, moveF(9, function(f)
				local idx = (f - 1 + k) % 9 + 1
				return (if on(idx) then path[idx] else HIDE_HEAD) - p0
			end))
		end
	end
end

-- Phantom Cape: a ghostly cape, pale (the colour), lined in the accent: a tall collar standing up behind the head and
-- flaring out at its sides (the lining showing inside it), the cape falling from the shoulders with a ghost's face on
-- its back (two hollow eyes and a round mouth in the accent), flaring to a tattered hem of five ragged points with
-- fainter tips. The lower half flutters, the points ripple one after another, their tips fade (faint, then gone, then
-- back), and wisps drift off the hem and are gone.
SPOOK.TATTERS = {
	-- { across, length, its ripple's phase, per frame of 8: 1 its tip shown, 2 faint, 0 gone }
	{ -0.92, 0.5, 0, "11122011" },
	{ -0.46, 0.4, 1.3, "11111220" },
	{ 0, 0.54, 2.6, "20111112" },
	{ 0.46, 0.42, 3.9, "11201111" },
	{ 0.92, 0.52, 5.2, "12201111" },
} :: { { any } }
BACK.phantom_cape = function(api, c, a, _ctx)
	local R = api.ROOT
	local F = CFrame.new(0, 1.5, -0.64) * ANG(0.12, 0, 0)
	api.add(R, 1.95, 0.3, 1.3, 0, 2.4, -0.05, c)
	api.add(R, 0.5, 0.1, 0.1, 0, 2.32, 0.65, a)
	-- the collar: up behind the head, leaning back, and a flap flaring out at each side, lined inside
	api.add(R, 2.6, 0.86, 0.2, 0, 2.8, -1.22, c, ANG(-0.45, 0, 0))
	api.add(R, 2.36, 0.7, 0.08, 0, 2.84, -1.08, a, ANG(-0.45, 0, 0))
	for _, sx in { -1, 1 } do
		api.add(R, 0.22, 0.8, 0.9, sx * 1.3, 2.75, -0.66, c, ANG(0, -sx * 0.35, sx * 0.35))
		api.add(R, 0.08, 0.64, 0.74, sx * 1.19, 2.8, -0.63, a, ANG(0, -sx * 0.35, sx * 0.35))
	end
	fput(api, R, F, 1.95, 1.3, 0.15, 0, 0.35, 0, c)
	for _, sx in { -1, 1 } do
		fput(api, R, F, 0.14, 1.3, 0.18, sx * 0.98, 0.35, 0, a)
		fput(api, R, F, 0.34, 0.5, 0.06, sx * 0.34, 0.5, -0.09, a)
	end
	fput(api, R, F, 0.3, 0.32, 0.06, 0, 0.04, -0.09, a)
	-- the lower half, flaring, and its points
	local P = F * CFrame.new(0, -0.3, 0)
	local low = api.count()
	fput(api, R, P, 2.3, 0.5, 0.14, 0, -0.25, -0.01, c)
	for _, sx in { -1, 1 } do
		fput(api, R, P, 0.14, 0.52, 0.17, sx * 1.1, -0.25, -0.01, a, ANG(0, 0, sx * 0.12))
	end
	for _, tt in SPOOK.TATTERS do
		local x, L, ph, pat = tt[1] :: number, tt[2] :: number, tt[3] :: number, tt[4] :: string
		local T = P * CFrame.new(x, -0.48, -0.01)
		local D = T * ANG(0, 0, PI)
		local t0 = api.count()
		fput(api, R, D, 0.47, L * 0.5, 0.12, 0, L * 0.25, 0, c)
		local tip = api.count()
		spike(api, R, D, 0.47, L * 0.6, 0.12, 0, L * 0.8, 0, c, L * 0.42)
		local fain = api.count()
		spike(api, R, D, 0.43, L * 0.56, 0.08, 0, L * 0.8, 0, "window", L * 0.4)
		local tp = (D * CFrame.new(0, L * 0.8, 0)).Position
		local gone = HIDE_ROOT - tp
		api.anim(tip, moveF(8, function(f)
			return if string.sub(pat, f, f) == "1" then Vector3.zero else gone
		end))
		api.anim(fain, moveF(8, function(f)
			return if string.sub(pat, f, f) == "0" then gone else Vector3.zero
		end))
		api.anim(t0, turnF(T, 8, function(f)
			return osc(f, 8, 0.22, ph), 0, osc(f, 8, 0.1, ph + 1)
		end))
	end
	api.anim(low, turnF(P, 8, function(f)
		return 0.08 + osc(f, 8, 0.08), 0, 0
	end))
	-- wisps drifting off the hem: back, out and up over five frames, out of sight in the torso the other three
	for k, x in { -0.6, 0.15, 0.7 } do
		local s0 = (P * CFrame.new(x, -0.95, -0.1)).Position
		local path: { Vector3 } = {}
		for f = 1, 5 do
			path[f] = s0 + Vector3.new(x * 0.12 * f, 0.1 * f, -0.14 * f)
		end
		path[6], path[7], path[8] = HIDE_ROOT, HIDE_ROOT, HIDE_ROOT
		local kk = (k - 1) * 3
		local w0 = api.count()
		local q = path[kk % 8 + 1]
		api.ball(R, 0.24 - 0.03 * k, q.X, q.Y, q.Z, "window")
		api.anim(w0, alongF(path, kk))
	end
end

-- Pumpkin Balloons: three jack-o'-lantern balloons floating over and behind the head, faces to the camera: squat
-- pumpkins (the colour) with green stems, black faces, a white shine and a knot, their strings curving up from a bow on
-- the back (the accent). Each bobs and sways about the bow on its own loop and tilts on its string.
SPOOK.BALLOONS = {
	-- { middle x, y, z, size, the bob's period and phase, the sway's period and phase, the tilt's period }
	{ -1.32, 4.98, -1.6, 0.94, 8, 2.0, 12, 1.0, 6 },
	{ 0.05, 5.58, -1.5, 1.12, 12, 0, 24, 0, 8 },
	{ 1.38, 5.1, -1.55, 0.88, 6, 3.1, 12, 4.2, 12 },
} :: { { number } }
BACK.pumpkin_balloons = function(api, c, a, _ctx)
	local R = api.ROOT
	local knot = Vector3.new(0, 2.05, -0.72)
	local Kn, inv = CFrame.new(knot), CFrame.new(-knot)
	TOY.bow(api, R, CFrame.new(0, 2.05, -0.6) * ANG(0, PI, 0), 0.7, 0.12, a, c)
	for i, b in SPOOK.BALLOONS do
		local d = b[4]
		local p = Vector3.new(b[1], b[2], b[3])
		local F = CFrame.new(p) * FACE_CAM
		local tie = p - Vector3.new(0, d * 0.4 + 0.1, 0)
		local from = api.count()
		local pts = { knot - Vector3.new(0, 0, 0.04), Vector3.new(p.X * 0.18, 2.5, -1.3), Vector3.new(p.X * 0.6, 3.6, p.Z - 0.04), tie }
		for k = 1, 3 do
			local q, r = pts[k], pts[k + 1]
			link(api, R, q.X, q.Y, q.Z, r.X, r.Y, r.Z, 0.09, "white")
		end
		local body = api.count()
		SPOOK.jack(api, R, F, d, c, a, "ink")
		fball(api, R, F, 0.18, 0, -d * 0.42, 0, c)
		fball(api, R, F, 0.16, -d * 0.2, d * 0.2, d * 0.3, "white")
		local tilt = b[9]
		api.anim(body, turnF(CFrame.new(tie), tilt, function(f)
			return 0, 0, osc(f, tilt, 0.12, i)
		end))
		local frames: { CFrame } = table.create(24)
		for f = 1, 24 do
			local sway = Kn * ANG(osc(f, b[7], 0.05, b[8] + 1.4), 0, osc(f, b[7], 0.09, b[8])) * inv
			frames[f] = CFrame.new(0, osc(f, b[5], 0.12, b[6]), 0) * sway
		end
		api.anim(from, frames)
	end
end

-- Bat Familiar: a little bat perched on the right shoulder, turned to the camera: a round black body (the colour) with
-- a purple tummy (the accent), a round head with big pointed ears (purple inside), white eyes with black pupils, two
-- tiny fangs, feet gripping the shoulder, and its wings (purple membranes on black bones) raised in a V. It flaps them
-- in bursts (three quick beats, then a rest), bobbing up on each downbeat, and now and then an ear twitches.
SPOOK.BAT_FLAP = { 0, 1.2, 0.3, 1.2, 0.3, 1.2, 0, 0, 0, 0, 0, 0 } -- radians down from the raised V, 12 frames
SPOOK.BAT_BOB = { 0, 0.07, 0.02, 0.07, 0.02, 0.07, 0, 0, 0, 0, 0, 0 }
SPOOK.BAT_EAR = { 0, 0, 0, 0, 0, 0, 0, 0, 0.5, 0.1, 0.5, 0 }
NECK.bat_familiar = function(api, c, a, ctx)
	local R = api.ROOT
	local k = 1.36
	-- (beside a jack-o'-lantern head, which is wider than a head, a little further out)
	local B = CFrame.new(if ctx.head then 1.52 else 1.38, 2.375 + 0.3 * k, 0.26) * ANG(0, 1.05, 0)
	local from = api.count()
	fball(api, R, B, 0.5 * k, 0, 0, 0, c)
	fball(api, R, B, 0.32 * k, 0, -0.04 * k, 0.12 * k, a)
	fball(api, R, B, 0.46 * k, 0, 0.36 * k, 0.02 * k, c)
	for _, sx in { -1, 1 } do
		-- the ears (the left one twitches), the eyes, a fang, a foot
		local E = B * CFrame.new(sx * 0.13 * k, 0.52 * k, 0) * ANG(0, 0, -sx * 0.25)
		local e0 = api.count()
		spike(api, R, E, 0.2 * k, 0.3 * k, 0.08 * k, 0, 0.15 * k, 0, c)
		spike(api, R, E, 0.1 * k, 0.18 * k, 0.06 * k, 0, 0.11 * k, 0.04 * k, a)
		if sx < 0 then
			api.anim(e0, turnF(E, 12, function(f)
				return 0, 0, SPOOK.BAT_EAR[f]
			end))
		end
		fball(api, R, B, 0.15 * k, sx * 0.1 * k, 0.4 * k, 0.18 * k, "white")
		fput(api, R, B, 0.07 * k, 0.09 * k, 0.04, sx * 0.1 * k, 0.39 * k, 0.26 * k, "ink")
		fput(api, R, B, 0.05 * k, 0.08 * k, 0.04, sx * 0.05 * k, 0.22 * k, 0.2 * k, "white", ANG(0, 0, sx * 0.3))
		fput(api, R, B, 0.1 * k, 0.1 * k, 0.14 * k, sx * 0.1 * k, -0.26 * k, 0.06 * k, c)
		-- the wing: a bone up and out from the shoulder to a claw, two membrane scallops under it
		local W = B * CFrame.new(sx * 0.2 * k, 0.1 * k, -0.06 * k) * ANG(0, 0, sx * 0.9)
		local w0 = api.count()
		fput(api, R, W, 0.62 * k, 0.08 * k, 0.08 * k, sx * 0.31 * k, 0, 0, c)
		fput(api, R, W, 0.1 * k, 0.1 * k, 0.1 * k, sx * 0.64 * k, 0.03 * k, 0, c, DIAMOND)
		fput(api, R, W, 0.36 * k, 0.3 * k, 0.05, sx * 0.2 * k, -0.17 * k, 0, a, ANG(0, 0, sx * 0.25))
		fput(api, R, W, 0.26 * k, 0.26 * k, 0.05, sx * 0.48 * k, -0.13 * k, 0, a, ANG(0, 0, -sx * 0.2))
		api.anim(w0, turnF(W, 12, function(f)
			return 0, 0, -sx * SPOOK.BAT_FLAP[f]
		end))
	end
	api.anim(from, moveF(12, function(f)
		return Vector3.new(0, SPOOK.BAT_BOB[f], 0)
	end))
end

-- Candy Corn Scythe: a tall black licorice handle banded in the colour, standing up in the fist from a little candy
-- corn of a pommel near the floor to above the shoulder (SPOOK.GRIP_STAFF), and at its top a great curved blade of candy
-- corn on a gold collar (its wide yellow root at the handle, the colour through its middle, a white point) sweeping out
-- and down, facing between the camera and the customization screen's view. A glint runs along its edge, and its point twinkles.
SPOOK.GRIP_STAFF = CFrame.new(1.06, 1.25, 0.18) * ANG(0.1, 0, -0.17)
HAND.candy_scythe = function(api, c, a, _ctx)
	local A = api.ARM_R
	local G = SPOOK.GRIP_STAFF
	local len, low = 2.7, 0.8
	fcyl(api, A, G, 0.18, len + low, (len - low) / 2, "black")
	for _, s in { -0.5, 0.42, 0.98, 1.54, 2.1 } do
		fcyl(api, A, G, 0.21, 0.16, s, c)
	end
	fcyl(api, A, G, 0.3, 0.14, -low - 0.06, a)
	fcyl(api, A, G, 0.22, 0.12, -low - 0.19, c)
	fcyl(api, A, G, 0.12, 0.1, -low - 0.3, "white")
	fcyl(api, A, G, 0.3, 0.24, len, "gold")
	local B = faceBoth(CFrame.new((G * CFrame.new(0, len + 0.05, 0)).Position) * CAM_SQ)
	-- the blade: eight pieces round an arc from the collar out and down to its point, narrowing as they go
	local N, r0 = 8, 0.94
	local cx, cy = -cos(1.95) * r0, 0.05 - sin(1.95) * r0
	local edge: { Vector3 } = {}
	for i = 0, N - 1 do
		local u0, u1 = i / N, (i + 1) / N
		local th0, th1 = 1.95 - u0 * 1.65, 1.95 - u1 * 1.65
		local w = 0.66 * (1 - 0.8 * (u0 + u1) / 2)
		local r = r0 - w / 2
		local um = (u0 + u1) / 2
		strip(api, A, B, cx + cos(th0) * r, cy + sin(th0) * r, cx + cos(th1) * r, cy + sin(th1) * r, w, 0.1, if um < 0.38 then a elseif um < 0.74 then c else "white")
		local re = r0 - w + 0.02
		edge[i + 1] = (B * CFrame.new(cx + cos((th0 + th1) / 2) * re, cy + sin((th0 + th1) / 2) * re, 0.08)).Position
	end
	-- the glint along the edge: five frames from the root to the point, out of sight in the arm the other seven
	local path: { Vector3 } = { edge[2], edge[3], edge[5], edge[6], edge[8] }
	for f = 6, 12 do
		path[f] = HIDE_ARM
	end
	local g0 = api.count()
	sparkle(api, A, CFrame.new(path[1]) * FACE_CAM, 0.3, "white")
	api.anim(g0, alongF(path, 0))
	local tip = (B * CFrame.new(cx + cos(0.3) * (r0 - 0.06), cy + sin(0.3) * (r0 - 0.06), 0.1)).Position
	glint(api, A, tip.X, tip.Y, tip.Z, 0.4, HIDE_ARM, "000000121000")
end

------------------------------------------------------------------ registry

local SLOTS: { [string]: { [string]: Draw } } = { hat = HAT, face = FACE, back = BACK, neck = NECK, hand = HAND }

for slot, kinds in SLOTS do
	for kind in kinds do
		AccessoryModels.KINDS[kind] = slot
	end
end

-- The Weekly Cup's wands and the reward wands, held up and out (GRIP_OUT); every other held piece is in GRIP.
local HELD_OUT: { [string]: boolean } = {
	marshmallow_wand = true,
	taffy_twirl_pop = true,
	biscuit_scepter = true,
	bamboo_whisk_wand = true,
	cupid_whisk = true,
	rocket_pop_wand = true,
	horseshoe_wand = true,
	golden_rolling_pin = true,
	bubble_wand = true,
	ribbon_wand = true,
}

-- The frame a held piece of `kind` is drawn in: the fist at its origin, x across the hand. A turned piece
-- (Data/Looks handTurn) turns about that x axis, so its handle stays in the fist. The Candy Corn Scythe stands upright
-- in the fist (SPOOK.GRIP_STAFF).
function AccessoryModels.grip(kind: string): CFrame
	return if kind == "candy_scythe" then SPOOK.GRIP_STAFF elseif HELD_OUT[kind] then GRIP_OUT else GRIP
end

function AccessoryModels.build(api: Api, slot: string, kind: string, color: string, accent: string, ctx: Ctx): boolean
	local kinds = SLOTS[slot]
	local draw = if kinds then kinds[kind] else nil
	if draw == nil then
		return false
	end
	draw(api, color, accent, ctx)
	return true
end

return AccessoryModels
