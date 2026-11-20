--!strict
-- Random Bakery's own free hats, faces and wings, its aprons and its bangs, ported with the rest of its customization
-- screen (the request of 2026-11-20; Data/Cosmetics pieces with a "b_" kind, Data/Looks' aprons and bangs). Drawn
-- through Models/AccessoryModels' Api in the bakery's body space (its header has the anchors); Models/WearModels fits
-- them onto the founder. Pure.
--   AccessoryBasics.build(api, slot, kind, c, a, ctx): boolean   draws a "b_" kind in colours c, a (already tinted)
--   AccessoryBasics.KINDS: { [string]: string }                   kind -> slot
--   AccessoryBasics.BOTTOM: { [string]: number }                  a covering hat's lower edge (the bakery's head space)
--   AccessoryBasics.apron(api, option, tint)                      an apron (Data/Looks.aprons) on the front of the torso
--   AccessoryBasics.bangs(api, id, color, streak, top)            bangs (Data/Looks.bangs) hanging from y `top`
local AccessoryModels = require(script.Parent.AccessoryModels)
local Looks = require(script.Parent.Parent.Data.Looks)

type Api = AccessoryModels.Api
-- the hair and skin colours, no hair, the shirt colour (the cap takes it) and the tint (nil: the piece's own colours)
export type Ctx = { hair: string, bald: boolean, skin: string, head: boolean?, top: string, tint: string? }

local AccessoryBasics = {}

-- A flame part's four spots as moves of the body (it leans and leaps from `at`, its rest place): the bakery's flicker.
local function flicker(at: Vector3, spots: { { number } }): { CFrame }
	local out: { CFrame } = {}
	for i, f in spots do
		out[i] = CFrame.new(at) * CFrame.new(f[1], f[2], 0) * CFrame.Angles(0, 0, f[3]) * CFrame.new(-at)
	end
	return out
end

-- A jack-o'-lantern in place of the head (a little bigger than it): a tall middle lobe between two lower side lobes,
-- diamond eyes and a grin with one tooth on the front, a stem with a leaf; the carving dark, the stem green (its
-- colours: `body` and `stem`, the piece's colours after the look's tint; a dark pumpkin's carving glows warm
-- inside, where ink would vanish into it).
local function pumpkinHead(api: Api, body: string?, stem: string?)
	local y = 3.5
	local orange, green = body or "orange", stem or "green"
	local dark: { [string]: boolean } = { black = true, sky_night = true, choco_dark = true, plate_lacquer = true, street = true }
	local carve = if dark[orange] then "oven_glow" else "ink"
	api.add(api.HEAD, 1.25, 2.1, 2.3, 0, y, 0, orange)
	api.add(api.HEAD, 0.75, 1.75, 2.0, -0.9, y - 0.05, 0, orange)
	api.add(api.HEAD, 0.75, 1.75, 2.0, 0.9, y - 0.05, 0, orange)
	-- the carving: eyes, a grin turned up at the corners, a tooth hanging from its top edge
	for _, sx in { -1, 1 } do
		api.add(api.HEAD, 0.5, 0.5, 0.1, sx * 0.45, y + 0.3, 1.17, carve, CFrame.Angles(0, 0, math.pi / 4))
		api.add(api.HEAD, 0.3, 0.3, 0.1, sx * 0.6, y - 0.3, 1.17, carve)
	end
	api.add(api.HEAD, 1.0, 0.4, 0.1, 0, y - 0.5, 1.17, carve)
	api.add(api.HEAD, 0.25, 0.2, 0.1, 0.15, y - 0.38, 1.2, orange)
	-- the stem and its leaf
	api.add(api.HEAD, 0.35, 0.6, 0.35, 0.05, y + 1.3, -0.05, green, CFrame.Angles(0, 0, -0.2))
	api.add(api.HEAD, 0.5, 0.15, 0.3, 0.4, y + 1.12, 0.1, green, CFrame.Angles(0, 0.3, -0.35))
end

-- Headless: no head at all, a flame burning up out of a high dark collar where the neck was. The flame is
-- Neon blocks narrowing to a tip and a wisp above it (a red root, orange tongues, a yellow heart showing on its front
-- and back, a pale hot core), two side tongues and an ember; they follow the neck (HEAD) and flicker: each has four spots
-- (dx, dy, turn) it steps through, 7 a second, the tip and the tongues leaping most, the ember rising and
-- sinking back into the heart.
-- stylua: ignore start
local FLAME: { { any } } = {
	-- { w, h, d, x, y, z, colour, frames }
	{ 1.4, 0.45, 1.05, 0, 2.92, 0, "berry_red", { { 0, 0, 0 }, { 0.04, 0, 0 }, { 0, 0.03, 0 }, { -0.04, 0, 0 } } },
	{ 1.2, 0.6, 0.95, 0, 3.38, 0, "orange", { { 0, 0, 0 }, { -0.07, 0.04, 0.04 }, { 0.05, 0, -0.03 }, { 0.07, 0.03, 0 } } },
	{ 0.85, 0.55, 0.75, 0, 3.92, 0, "orange", { { 0, 0, 0 }, { 0.1, 0.05, -0.1 }, { -0.07, -0.03, 0.08 }, { 0.05, 0.06, 0.06 } } },
	{ 0.45, 0.5, 0.45, 0, 4.42, 0, "orange", { { 0, 0, 0 }, { -0.14, 0.12, 0.25 }, { 0.12, -0.07, -0.2 }, { 0.06, 0.14, -0.1 } } },
	{ 0.22, 0.32, 0.22, 0.05, 4.84, 0, "orange", { { 0, 0, 0 }, { -0.2, 0.16, 0.35 }, { 0.16, -0.12, -0.3 }, { 0.1, 0.2, -0.2 } } },
	{ 0.9, 0.55, 1.1, 0, 3.02, 0, "yellow", { { 0, 0, 0 }, { 0.03, 0, 0 }, { -0.03, 0, 0 }, { 0, 0.03, 0 } } },
	{ 0.62, 0.5, 1.0, 0, 3.5, 0, "yellow", { { 0, 0, 0 }, { -0.05, 0.04, 0 }, { 0.04, -0.03, 0 }, { 0.05, 0.04, 0 } } },
	{ 0.34, 0.4, 0.8, 0, 3.95, 0, "cream", { { 0, 0, 0 }, { 0.07, 0.06, 0.1 }, { -0.06, -0.04, -0.1 }, { 0.03, 0.07, 0 } } },
	{ 0.32, 0.5, 0.32, -0.68, 3.42, 0, "orange", { { 0, 0, 0 }, { -0.05, 0.18, 0.15 }, { 0.03, -0.1, 0 }, { -0.03, 0.1, 0.1 } } },
	{ 0.32, 0.5, 0.32, 0.68, 3.42, 0, "orange", { { 0, 0.12, 0 }, { 0.04, -0.07, 0 }, { 0.06, 0.19, -0.15 }, { 0, 0, 0 } } },
	{ 0.2, 0.2, 0.2, 0.28, 5.1, 0, "yellow", { { 0, 0, 0 }, { 0.06, 0.35, 0 }, { 0, 0.7, 0 }, { -0.28, -1.6, 0 } } },
}
-- stylua: ignore end

-- `tint` (the look's hat colour, Data/Looks.tintOf): the flame burns in it, root and tongues in the tint round a cream heart
-- and a white core, Neon and flickering as ever.
local function headlessFlame(api: Api, tint: string?)
	local hot: { [string]: string } = { yellow = "cream", cream = "white" }
	-- the collar: a dark ruff on the shoulders, a little higher at the back
	api.add(api.ROOT, 1.75, 0.3, 1.25, 0, 2.6, 0, "black")
	api.add(api.ROOT, 1.5, 0.25, 0.3, 0, 2.85, -0.5, "black")
	for _, f in FLAME do
		local c: string = f[7]
		if tint then
			c = hot[c] or tint
		end
		api.add(api.HEAD, f[1], f[2], f[3], f[4], f[5], f[6], c)
		api.glow()
		api.anim(api.count() - 1, flicker(Vector3.new(f[4], f[5], f[6]), f[8]))
	end
end

-- The hats (all HEAD parts). The head top is y 4.5; an uncovered hair cap reaches 4.75. `ctx.top` is the shirt colour
-- (the cap is drawn in it), `ctx.bald` lowers what sits on the hair. Cat ears come in the hair colour (their piece
-- has no colour of its own: WearModels passes the hair's).
local function hat(api: Api, id: string, c: string, a: string, ctx: Ctx)
	local top, t, bald = ctx.top, ctx.tint, ctx.bald
	local lift = if bald then -0.2 else 0
	if id == "toque" then
		api.add(api.HEAD, 1.75, 0.5, 1.75, 0, 4.75, 0, c)
		api.add(api.HEAD, 2, 0.75, 2, 0, 5.375, 0, c)
		api.ball(api.HEAD, 0.75, -0.45, 5.75, 0.1, c)
		api.ball(api.HEAD, 0.75, 0.45, 5.75, -0.1, c)
	elseif id == "tall_toque" then
		api.add(api.HEAD, 1.75, 0.5, 1.75, 0, 4.75, 0, c)
		api.add(api.HEAD, 1.75, 1, 1.75, 0, 5.5, 0, c)
		api.add(api.HEAD, 2.25, 0.75, 2.25, 0, 6.375, 0, c)
		api.ball(api.HEAD, 0.75, -0.5, 6.8, 0.1, c)
		api.ball(api.HEAD, 0.75, 0.5, 6.8, -0.1, c)
		api.ball(api.HEAD, 0.75, 0, 6.9, 0.35, c)
	elseif id == "beret" then
		api.add(api.HEAD, 2, 0.5, 2, 0.15, 4.85 + lift, -0.1, c, CFrame.Angles(0, 0, -0.15))
		api.add(api.HEAD, 0.25, 0.25, 0.25, 0.15, 5.2 + lift, -0.1, c)
	elseif id == "bandana" then
		api.add(api.HEAD, 2.25, 0.75, 2.25, 0, 4.55, -0.05, c)
		api.add(api.HEAD, 0.25, 0.25, 0.25, -0.5, 4.6, 1.1, a)
		api.add(api.HEAD, 0.25, 0.25, 0.25, 0.4, 4.45, 1.1, a)
		api.add(api.HEAD, 0.5, 0.5, 0.25, 0, 4.35, -1.25, c)
		api.add(api.HEAD, 0.25, 0.75, 0.25, -0.2, 3.85, -1.3, c, CFrame.Angles(0, 0, 0.2))
		api.add(api.HEAD, 0.25, 0.75, 0.25, 0.2, 3.85, -1.3, c, CFrame.Angles(0, 0, -0.2))
	elseif id == "cap" then
		-- in the outfit's colour (a white or cream outfit: the cap's own blue), or its tint
		local capColor = if t or top == "white" or top == "cream" then c else top
		api.add(api.HEAD, 2.25, 0.75, 2.25, 0, 4.625, -0.05, capColor)
		api.add(api.HEAD, 2, 0.25, 1, 0, 4.375, 1.4, capColor)
		api.add(api.HEAD, 0.5, 0.25, 0.5, 0, 5.1, -0.05, a)
	elseif id == "beanie" then
		api.add(api.HEAD, 2.5, 0.5, 2.5, 0, 4.35, -0.05, a)
		api.add(api.HEAD, 2.25, 0.75, 2.25, 0, 4.95, -0.05, c)
		api.add(api.HEAD, 1.5, 0.25, 1.5, 0, 5.45, -0.05, c)
		api.ball(api.HEAD, 0.75, 0, 5.8, -0.05, a)
	elseif id == "cupcake" then
		api.add(api.HEAD, 2, 0.75, 2, 0, 4.75, 0, c)
		api.add(api.HEAD, 2.25, 0.5, 2.25, 0, 5.35, 0, a)
		api.add(api.HEAD, 1.5, 0.5, 1.5, 0, 5.85, 0, a)
		api.ball(api.HEAD, 0.5, 0, 6.3, 0, "berry_red")
		api.add(api.HEAD, 0.25, 0.25, 0.25, -0.75, 5.5, 0.9, "blue")
		api.add(api.HEAD, 0.25, 0.25, 0.25, 0.6, 5.45, 0.95, "yellow")
	elseif id == "bunny_ears" then
		api.add(api.HEAD, 0.5, 1.75, 0.25, -0.5, 5.5 + lift, 0, c, CFrame.Angles(0, 0, 0.15))
		api.add(api.HEAD, 0.5, 1.75, 0.25, 0.5, 5.5 + lift, 0, c, CFrame.Angles(0, 0, -0.15))
		api.add(api.HEAD, 0.25, 1.25, 0.25, -0.5, 5.5 + lift, 0.1, a, CFrame.Angles(0, 0, 0.15))
		api.add(api.HEAD, 0.25, 1.25, 0.25, 0.5, 5.5 + lift, 0.1, a, CFrame.Angles(0, 0, -0.15))
	elseif id == "cat_ears" then
		-- in the hair colour, or the tint
		local ear, inner = c, a
		for _, sx in { -1, 1 } do
			api.add(api.HEAD, 0.5, 0.75, 0.25, sx * 0.65, 4.95 + lift, 0.1, ear, CFrame.Angles(0, 0, -sx * 0.3))
			api.add(api.HEAD, 0.25, 0.5, 0.25, sx * 0.65, 4.9 + lift, 0.2, inner, CFrame.Angles(0, 0, -sx * 0.3))
		end
	elseif id == "witch_hat" then
		-- a wide black brim, a purple cone bending back to a tip, a gold band (the trick-or-treaters' hat)
		api.add(api.HEAD, 3, 0.25, 3, 0, 4.875 + lift, 0, a)
		api.add(api.HEAD, 1.75, 0.75, 1.75, 0, 5.25 + lift, 0, c)
		api.add(api.HEAD, 1.25, 0.75, 1.25, 0.1, 5.95 + lift, -0.05, c, CFrame.Angles(0, 0, -0.1))
		api.add(api.HEAD, 0.75, 0.75, 0.75, 0.3, 6.6 + lift, -0.1, c, CFrame.Angles(0, 0, -0.3))
		api.add(api.HEAD, 1.75, 0.25, 1.75, 0, 5.0 + lift, 0, "gold")
		api.add(api.HEAD, 0.5, 0.25, 0.1, 0, 5.0 + lift, 0.9, "yellow")
	elseif id == "pumpkin_head" then
		pumpkinHead(api, c, a)
	elseif id == "headless" then
		headlessFlame(api, t)
	elseif id == "moth_antennae" then
		-- two feathery antennae from the hairline, leaning out and curving further out as they rise: a thin stalk
		-- in the accent through a comb of plumes that is widest in its middle (a feather from the front, a slimmer one
		-- from the side)
		for _, sx in { -1, 1 } do
			local base = CFrame.new(sx * 0.32, 4.6 + lift, 0.4) * CFrame.Angles(0, 0, -sx * 0.3)
			local function piece(w: number, h: number, d: number, up: number, color: string, turn: number)
				local cf = base * CFrame.new(-sx * turn * up * 0.4, up, 0) * CFrame.Angles(0, 0, -sx * turn)
				api.add(api.HEAD, w, h, d, cf.X, cf.Y, cf.Z, color, cf.Rotation)
			end
			piece(0.12, 0.7, 0.14, 0.35, a, 0)
			for k, w in { 0.36, 0.6, 0.72, 0.62, 0.42 } do
				local up = 0.5 + 0.27 * k
				piece(w, 0.3, w * 0.5, up, c, 0.06 * k)
				piece(0.12, 0.3, w * 0.5 + 0.06, up, a, 0.06 * k)
			end
			piece(0.2, 0.26, 0.14, 2.05, c, 0.5)
		end
	elseif id == "devil_horns" then
		-- two little horns on the head top, each leaning out from a wide root and curling back in at the tip
		for _, sx in { -1, 1 } do
			api.add(api.HEAD, 0.5, 0.4, 0.45, sx * 0.55, 4.85 + lift, 0.15, a, CFrame.Angles(0, 0, -sx * 0.25))
			api.add(api.HEAD, 0.38, 0.34, 0.36, sx * 0.68, 5.15 + lift, 0.15, c, CFrame.Angles(0, 0, -sx * 0.35))
			api.add(api.HEAD, 0.26, 0.3, 0.26, sx * 0.75, 5.42 + lift, 0.15, c, CFrame.Angles(0, 0, sx * 0.05))
			api.add(api.HEAD, 0.15, 0.22, 0.15, sx * 0.7, 5.62 + lift, 0.15, c, CFrame.Angles(0, 0, sx * 0.5))
		end
	elseif id == "flower" then
		local x, y, z = 0.7, 4.45 + lift, 1.15
		api.add(api.HEAD, 0.25, 0.25, 0.25, x, y, z, a)
		api.add(api.HEAD, 0.25, 0.25, 0.25, x - 0.25, y, z, c)
		api.add(api.HEAD, 0.25, 0.25, 0.25, x + 0.25, y, z, c)
		api.add(api.HEAD, 0.25, 0.25, 0.25, x, y + 0.25, z, c)
		api.add(api.HEAD, 0.25, 0.25, 0.25, x, y - 0.25, z, c)
	end
end

-- Face accessories (HEAD parts on the face, front at z 1). Eyes sit at (+-0.45, 3.4).
local function face(api: Api, id: string, c: string, a: string, _ctx: Ctx)
	-- the cheeks (in the Blush's own colour, which its tint changes; under shades and the rest always pink)
	local function blush(cheek: string?)
		api.add(api.HEAD, 0.5, 0.25, 0.25, -0.75, 3, 0.95, cheek or "pink")
		api.add(api.HEAD, 0.5, 0.25, 0.25, 0.75, 3, 0.95, cheek or "pink")
	end
	if id == "blush" then
		blush(c)
	elseif id == "glasses" then
		api.add(api.HEAD, 2, 0.25, 0.25, 0, 3.775, 1.05, c)
		api.add(api.HEAD, 0.25, 0.5, 0.25, -0.95, 3.4, 1.05, c)
		api.add(api.HEAD, 0.25, 0.5, 0.25, 0.95, 3.4, 1.05, c)
		api.add(api.HEAD, 0.75, 0.25, 0.25, -0.45, 3.025, 1.05, c)
		api.add(api.HEAD, 0.75, 0.25, 0.25, 0.45, 3.025, 1.05, c)
	elseif id == "shades" then
		api.add(api.HEAD, 2, 0.25, 0.25, 0, 3.55, 1.05, c)
		api.add(api.HEAD, 0.75, 0.5, 0.25, -0.45, 3.4, 1.1, c)
		api.add(api.HEAD, 0.75, 0.5, 0.25, 0.45, 3.4, 1.1, c)
		blush()
	elseif id == "freckles" then
		for _, sx in { -1, 1 } do
			api.add(api.HEAD, 0.25, 0.25, 0.25, sx * 0.6, 3.05, 0.95, c)
			api.add(api.HEAD, 0.25, 0.25, 0.25, sx * 0.85, 2.85, 0.95, c)
		end
	elseif id == "vampire_fangs" then
		-- a dark smile with a white fang under each end
		api.add(api.HEAD, 0.6, 0.1, 0.1, 0, 2.92, 1.02, a)
		api.add(api.HEAD, 0.14, 0.24, 0.1, -0.2, 2.78, 1.03, c)
		api.add(api.HEAD, 0.14, 0.24, 0.1, 0.2, 2.78, 1.03, c)
		blush()
	elseif id == "masquerade_mask" then
		-- a band across the eyes (they look out of its holes) with its outer corners swept up into points, a jewel
		-- on each point; the cheeks stay bare under it
		api.add(api.HEAD, 1.9, 0.14, 0.1, 0, 3.72, 1.05, c)
		api.add(api.HEAD, 0.56, 0.36, 0.1, 0, 3.47, 1.05, c)
		for _, sx in { -1, 1 } do
			api.add(api.HEAD, 0.6, 0.14, 0.1, sx * 0.44, 3.1, 1.05, c)
			api.add(api.HEAD, 0.34, 0.62, 0.1, sx * 0.76, 3.41, 1.05, c)
			api.add(api.HEAD, 0.3, 0.3, 0.1, sx * 0.88, 3.76, 1.04, c, CFrame.Angles(0, 0, sx * 0.6))
			api.add(api.HEAD, 0.14, 0.14, 0.1, sx * 0.96, 3.86, 1.1, a, CFrame.Angles(0, 0, math.pi / 4))
		end
	elseif id == "moustache" then
		-- in the hair colour, or the tint
		local m = c
		api.add(api.HEAD, 1, 0.25, 0.25, 0, 2.9, 1.05, m)
		api.add(api.HEAD, 0.25, 0.25, 0.25, -0.625, 3.0, 1.05, m)
		api.add(api.HEAD, 0.25, 0.25, 0.25, 0.625, 3.0, 1.05, m)
		blush()
	end
end

-- The apron on the front of the torso (x -0.625..0.625, y 0.525..2.275): plain with a pocket, vertical stripes,
-- horizontal bands or dots.
-- `t`: the look's apron colour (Data/Looks.tintOf "apron"): the body, a pattern's base, the cloak, the candy corn's
-- middle band take it; stripes, bands, dots, the clasp and the corn's other bands keep their own (Data/Looks.tinted).
function AccessoryBasics.apron(api: Api, o: Looks.Option?, t: string?)
	local pattern = if o and o.pattern then o.pattern else "plain"
	if pattern == "none" then
		return
	end
	local c, a = Looks.tinted(if o and o.color then o.color else "cream", if o and o.accent then o.accent else "white", t)
	if pattern == "cloak" then
		-- a ragged cloak in place of the apron: a mantle over the shoulders, a hood fallen behind the head, a long
		-- back with a torn hem, two front panels hanging open over the outfit (ragged ends), a clasp in the accent
		api.add(api.ROOT, 2.25, 0.5, 1.5, 0, 2.35, -0.05, c)
		api.add(api.ROOT, 1.75, 0.5, 0.5, 0, 2.65, -1.2, c, CFrame.Angles(-0.25, 0, 0))
		api.add(api.ROOT, 2, 1.75, 0.25, 0, 1.4, -0.68, c, CFrame.Angles(0.1, 0, 0))
		for i, x in { -0.75, 0, 0.7 } do
			local h = if i == 2 then 0.25 else 0.5
			api.add(api.ROOT, 0.5, h, 0.25, x, 0.55 - h / 2 + 0.05, -0.74, c, CFrame.Angles(0.1, 0, (i - 2) * 0.15))
		end
		for _, sx in { -1, 1 } do
			api.add(api.ROOT, 0.5, 1.5, 0.25, sx * 0.55, 1.55, 0.55, c)
			api.add(api.ROOT, 0.25, 0.5, 0.25, sx * (if sx < 0 then 0.68 else 0.45), 0.6, 0.55, c, CFrame.Angles(0, 0, sx * 0.2))
		end
		api.add(api.ROOT, 0.25, 0.25, 0.25, -0.3, 2.3, 0.75, a, CFrame.Angles(0, 0, math.pi / 4))
		api.add(api.ROOT, 0.25, 0.25, 0.25, 0.3, 2.3, 0.75, a, CFrame.Angles(0, 0, math.pi / 4))
		return
	end
	if pattern == "corn" then
		-- candy corn: the colour in the middle, the accent across the bottom, the white tip a narrower bib on top
		api.add(api.ROOT, 1.25, 0.6, 0.25, 0, 0.825, 0.55, a)
		api.add(api.ROOT, 1.25, 0.65, 0.25, 0, 1.45, 0.55, c)
		api.add(api.ROOT, 0.85, 0.5, 0.25, 0, 2.025, 0.55, if c == "white" then "cream" else "white")
		return
	end
	if pattern == "stripes" then
		for i = 0, 4 do
			api.add(api.ROOT, 0.25, 1.75, 0.25, -0.5 + 0.25 * i, 1.4, 0.55, if i % 2 == 0 then c else a)
		end
	elseif pattern == "bands" then
		for i = 0, 6 do
			api.add(api.ROOT, 1.25, 0.25, 0.25, 0, 0.65 + 0.25 * i, 0.55, if i % 2 == 0 then c else a)
		end
	else
		api.add(api.ROOT, 1.25, 1.75, 0.25, 0, 1.4, 0.55, c)
		if pattern == "dots" then
			for _, d in { { -0.3, 1.95 }, { 0.3, 1.6 }, { -0.3, 1.25 }, { 0.3, 0.9 } } do
				api.add(api.ROOT, 0.25, 0.25, 0.25, d[1], d[2], 0.6, a)
			end
		else
			api.add(api.ROOT, 0.5, 0.25, 0.25, 0, 1.15, 0.7, if c == "white" then "cream" else "white")
		end
	end
end

-- Wings on the back (the back slot; ROOT parts, so they lean and turn with the body). Each wing is flat panels
-- in its own frame: from a root by the spine (the torso's back is at z -0.5) its x runs out past the shoulder and
-- turns back (a V from above, so a wing shows from the side too), y up. Markings are a touch thicker than the panel they lie on, so they show on both faces.
-- The moths: a broad forewing swept up beside the head (its tip in the accent, an eyespot) over a rounder hindwing;
-- the luna moth's leading edge in the accent, a yellow eyespot on each wing and a long tail from each hindwing. The
-- bat: an arm bone in the accent out to a claw, the membrane hanging from it in three scallops between finger bones.
local function back(api: Api, id: string, c: string, a: string, _ctx: Ctx)
	-- the body the wings grow from, down the spine between them
	api.add(api.ROOT, 0.5, 1.1, 0.22, 0, 2.0, -0.62, if id == "bat_wings" then c else a)
	for _, sx in { -1, 1 } do
		local W = CFrame.new(sx * 0.3, 2.3, -0.62) * CFrame.Angles(0, sx * 0.42, 0)
		-- a panel's frame: (lx, ly) in the wing's frame, turned `turn` (up and out for the wing on either side)
		local function at(lx: number, ly: number, turn: number): CFrame
			return W * CFrame.new(sx * lx, ly, 0) * CFrame.Angles(0, 0, sx * turn)
		end
		local function panel(F: CFrame, dx: number, dy: number, w: number, h: number, d: number, color: string, name: string)
			local cf = F * CFrame.new(sx * dx, dy, 0)
			api.add(api.ROOT, w, h, d, cf.X, cf.Y, cf.Z, color, cf.Rotation)
		end
		if id == "bat_wings" then
			-- the arm bone from the spine out to a claw; under it the membrane in three panels, each shorter than
			-- the one inside it (a scallop's point at each finger bone)
			local x0, y0, x1, y1 = 0.13, 0.2, 2.1, 1.75
			local ang = math.atan2(y1 - y0, x1 - x0)
			local function on(t: number): (number, number)
				return x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
			end
			panel(at((x0 + x1) / 2, (y0 + y1) / 2, ang), 0, 0, 2.55, 0.22, 0.18, a, "WingBone")
			panel(at(x1 + 0.1, y1 + 0.12, ang + 0.6), 0, 0, 0.38, 0.18, 0.18, a, "WingBone")
			for i, sp in { { 0.17, 1.75, 0.92, 0.2 }, { 0.48, 1.45, 0.85, 0.36 }, { 0.78, 1.1, 0.78, 0.52 } } do
				local px, py = on(sp[1])
				panel(at(px, py - sp[2] / 2 + 0.08, sp[4]), 0, 0, sp[3], sp[2], 0.12, c, "Wing")
				if i < 3 then
					-- the finger bone between this panel and the next, down to the scallop's point
					local fx, fy = on(sp[1] + 0.16)
					local len = sp[2] * 0.85
					panel(at(fx, fy - len / 2, -0.06), 0, 0, 0.1, len, 0.16, a, "WingBone")
				end
			end
		else
			local luna = id == "luna_wings"
			-- the forewing swept up beside the head, its tip rounded off; the hindwing below it
			local fore = at(0.95, 0.95, 0.62)
			panel(fore, 0, 0, 2.0, 1.35, 0.12, c, "Wing")
			local tip = at(1.8, 1.72, 0.95)
			panel(tip, 0, 0, 0.72, 0.62, 0.12, c, "Wing")
			local hind = at(0.7, -0.45, -0.5)
			panel(hind, 0, 0, 1.45, 1.1, 0.12, c, "Wing")
			if luna then
				-- the leading edge, an eyespot on each wing and a long tail from the hindwing
				panel(fore, 0, 0.6, 2.0, 0.16, 0.16, a, "WingEdge")
				panel(tip, -0.04, 0.25, 0.66, 0.14, 0.16, a, "WingEdge")
				panel(fore, 0.2, -0.05, 0.4, 0.4, 0.18, "yellow", "Eyespot")
				panel(fore, 0.2, -0.05, 0.16, 0.16, 0.2, a, "Eyespot")
				panel(hind, 0.15, 0.02, 0.34, 0.34, 0.18, "yellow", "Eyespot")
				local tail = hind * CFrame.new(sx * 0.62, -0.95, 0) * CFrame.Angles(0, 0, sx * 0.35)
				panel(tail, 0, 0, 0.26, 1.0, 0.12, c, "Wing")
				panel(tail, 0, -0.55, 0.22, 0.3, 0.16, a, "WingEdge")
			else
				-- a dark tip, an eyespot on the forewing, a spot on the hindwing
				panel(tip, 0.06, 0.02, 0.6, 0.56, 0.16, a, "WingEdge")
				panel(fore, 0.22, -0.08, 0.44, 0.44, 0.18, a, "Eyespot")
				panel(fore, 0.22, -0.08, 0.18, 0.18, 0.2, "cream", "Eyespot")
				panel(hind, 0.18, -0.05, 0.34, 0.34, 0.16, a, "Eyespot")
			end
		end
	end
end

-- Two loops of moves one after the other (`outer` after `inner`, frame by frame), as long as both together repeat
-- Bangs: the front of the hair over the brow in place of the style's own, hanging from `top` (the hair cap's front
-- edge, or a covering hat's lower edge) and never over the eyes; the middle bang takes the second colour (`streak`).
function AccessoryBasics.bangs(api: Api, bangs: string, color: string, streak: string, top: number)
	local function piece(sx: number, sy: number, sz: number, x: number, y: number, z: number, col: string, rot: CFrame?)
		api.add(api.HEAD, sx, sy, sz, x, y, z, col, rot)
	end
	local bz = 0
	local function hang(want: number): number
		return math.max(0.15, math.min(want, top - 3.72))
	end
	local function strand(w: number, h: number, x: number, col: string, tilt: number?, z: number?)
		piece(w, h, 0.45, x, top - h / 2, (z or 0.95) + bz, col, if tilt then CFrame.Angles(0, 0, tilt) else nil)
	end
	local two = streak ~= color
	if bangs == "blunt" then
		local h = hang(0.7)
		piece(2.25, h, 0.5, 0, top - h / 2, 0.92 + bz, color)
		if two then
			piece(0.5, h + 0.06, 0.5, 0, top - (h + 0.06) / 2, 0.95 + bz, streak)
		end
	elseif bangs == "cropped" then
		local h = hang(0.28)
		piece(2.25, h, 0.5, 0, top - h / 2, 0.9 + bz, color)
		if two then
			piece(0.5, h + 0.1, 0.5, 0, top - (h + 0.1) / 2, 0.93 + bz, streak)
		end
	elseif bangs == "sidepart" then
		-- parted over the right brow: a long sweep to the left, a short tuft to the right
		local h = hang(0.62)
		strand(1.45, h, -0.38, color, -0.1)
		strand(0.7, hang(0.3), 0.78, color, 0.05)
		if two then
			strand(0.45, h + 0.04, -0.02, streak, -0.1, 0.98)
		end
	elseif bangs == "parted" then
		-- parted in the middle, falling away to either side
		local h = hang(0.6)
		strand(0.95, h, -0.62, color, 0.28)
		strand(0.95, h, 0.62, color, -0.28)
		if two then
			strand(0.3, h, -0.26, streak, 0.28, 0.98)
			strand(0.3, h, 0.26, streak, -0.28, 0.98)
		end
	elseif bangs == "wispy" then
		-- thin separate strands of different lengths
		piece(2.25, 0.2, 0.5, 0, top - 0.1, 0.9 + bz, color)
		local lens = { 0.45, 0.6, 0.55, 0.62, 0.42 }
		for i, x in { -0.8, -0.4, 0, 0.4, 0.8 } do
			strand(0.28, hang(lens[i]), x, if i == 3 then streak else color, -x * 0.08)
		end
	elseif bangs == "pointy" then
		-- a row of points down over the brow
		piece(2.25, 0.25, 0.5, 0, top - 0.125, 0.9 + bz, color)
		local d = math.clamp(hang(0.6) * 0.6, 0.18, 0.42)
		for i, x in { -0.8, -0.4, 0, 0.4, 0.8 } do
			piece(d, d, 0.4, x, top - 0.12 - d * 0.5, 0.95 + bz, if i == 3 then streak else color, CFrame.Angles(0, 0, math.pi / 4))
		end
	elseif bangs == "swoop" then
		-- one big sweep across the brow, curling at its end
		local h = hang(0.5)
		piece(2.1, h, 0.5, 0.05, top - h / 2 - 0.08, 0.94 + bz, color, CFrame.Angles(0, 0, -0.22))
		api.ball(api.HEAD, 0.45, 0.95, math.max(3.85, top - h - 0.1), 1.0 + bz, color)
		if two then
			piece(0.45, h + 0.05, 0.5, 0, top - h / 2 - 0.08, 0.97 + bz, streak, CFrame.Angles(0, 0, -0.22))
		end
	elseif bangs == "three" then
		-- three tapered strands, the brow showing between them; the sides lean out a little
		piece(2.25, 0.2, 0.5, 0, top - 0.1, 0.9 + bz, color)
		local d = 0.36 -- the point: a diamond as wide as the strand
		for i, sp in { { -0.66, 0.62, 0.12 }, { 0, 0.74, 0 }, { 0.66, 0.62, -0.12 } } do
			local x, tilt = sp[1], sp[3]
			local col = if i == 2 then streak else color
			local body = math.max(0.08, hang(sp[2]) - d * 0.7)
			strand(0.5, body, x, col, tilt)
			local bx = x + body / 2 * math.sin(tilt)
			local by = top - body / 2 - body / 2 * math.cos(tilt)
			piece(d, d, 0.4, bx, by, 0.95 + bz, col, CFrame.Angles(0, 0, math.pi / 4 + tilt))
		end
	end
	-- ("none": a bare brow, the hair swept back)
end

AccessoryBasics.KINDS = {
	b_toque = "hat", b_tall_toque = "hat", b_beret = "hat", b_bandana = "hat", b_cap = "hat", b_beanie = "hat",
	b_cupcake = "hat", b_bunny_ears = "hat", b_cat_ears = "hat", b_flower = "hat", b_witch_hat = "hat",
	b_pumpkin_head = "hat", b_headless = "hat", b_moth_antennae = "hat", b_devil_horns = "hat",
	b_blush = "face", b_glasses = "face", b_shades = "face", b_freckles = "face", b_moustache = "face",
	b_vampire_fangs = "face", b_masquerade_mask = "face",
	b_moth_wings = "back", b_luna_wings = "back", b_bat_wings = "back",
} :: { [string]: string }

-- the lower edge (y) of the hats that cover the top of the head
AccessoryBasics.BOTTOM = { b_toque = 4.5, b_tall_toque = 4.5, b_bandana = 4.175, b_cap = 4.25, b_beanie = 4.1, b_cupcake = 4.375 } :: { [string]: number }

local DRAW: { [string]: (api: Api, id: string, c: string, a: string, ctx: Ctx) -> () } = { hat = hat, face = face, back = back }

function AccessoryBasics.build(api: Api, slot: string, kind: string, c: string, a: string, ctx: Ctx): boolean
	if AccessoryBasics.KINDS[kind] ~= slot then
		return false
	end
	DRAW[slot](api, string.sub(kind, 3), c, a, ctx)
	return true
end

return AccessoryBasics
