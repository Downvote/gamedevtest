--!strict
-- Body plans sculpted on the smooth solids (Models/DriftAnatomy, Models/DriftKit; GAME_DESIGN 6; the request of
-- 2026-11-15: "can you redo all the creatures and eggs and add alot more extra ones with more variation to them?
-- currently, all of them are modelled using blobs, which is unnatural. reference other models online to see how you
-- should model them"). Each plan returns its Thing, facing +Z with its feet on the ground at y 0; `forms` gives each
-- species of these plans its own variation (Data/Creatures id -> the form its plan reads).
local Kit = require(script.Parent.DriftKit)
local A = require(script.Parent.DriftAnatomy)

local V = Vector3.new
local R = math.rad
local J = Kit.J
local full = Kit.full
local UP, FWD = A.UP, A.FWD

type Form = { [string]: any }
local PLANS: { [string]: (b: string, a: string, form: Form?) -> Kit.Thing } = {}
local FORMS: { [string]: Form } = {}

------------------------------------------------------------------ the pup (fox, dog, wolf)
-- A young fox: a deep chest and slimmer hips, a big head with a long pointed muzzle and a black nose, tall pointed
-- ears with pale insides and dark tips, a cream bib, slim forelegs straight down to round paws, hind legs bending at
-- the hock, dark socks, a big brush of a tail with a pale tip.
PLANS.pup = function(b, a, form)
	local f: Form = form or {}
	local t = Kit.new("pup", 2.2, 1.1, "quad")
	local ink = A.ink(b, a)
	local under = f.under or A.under(b)
	local sock = f.sock or (if A.isDark(b) then a else "black")
	J("body", nil, V(0, 0.85, 0), "body")
	local _, body = A.body("Body", V(0, 0.92, -0.04), V(0, 0.12, 1).Unit, 1.32, 0.74, 0.7, 0.56, b)
	-- the bib and belly: a pale cap on the chest's front and underside
	A.patch("Bib", body, V(0, -0.35, 1), 0.86, 0.03, under)
	A.patch("Belly", body, V(0, -1, 0.15), V(0.72, 0.8, 0.7), 0.02, under, true)
	-- the neck, rising from the top of the chest
	Kit.limb("Neck", V(0, 1.02, 0.42), V(0, 1.3, 0.6), 0.27, 0.23, b)
	-- legs: forelegs from the shoulders, hind legs from the haunches
	for _, l in { { n = "FL", s = -1, z = 0.36, ph = 0 }, { n = "FR", s = 1, z = 0.36, ph = 0.5 }, { n = "BL", s = -1, z = -0.42, ph = 0.5 }, { n = "BR", s = 1, z = -0.42, ph = 0 } } do
		local hind = l.z < 0
		A.leg(l.n, l.s, l.ph, V(l.s * 0.22, 0.84, l.z), {
			kind = if hind then "hind" else "fore",
			r = if hind then 0.13 else 0.115,
			c = b,
			sock = sock,
			fc = sock,
			fw = 0.24,
			pad = "pink",
			out = 0.02,
		})
	end
	-- the tail: a big brush with a pale tip
	A.tail(V(0, 1.0, -0.66), { kind = "brush", len = 1.3, r = 0.17, c = b, tip = under, up = 24, curl = 40 })
	-- the head
	local h = A.head({
		c = V(0, 1.66, 0.76),
		size = V(1.02, 0.9, 0.9),
		color = b,
		pivot = V(0, 1.3, 0.6),
		muzzle = "fox",
		mlen = 0.46,
		mw = 0.36,
		mdrop = 0.15,
		nose = ink,
		cheeks = under,
		eye = { R(32), R(8), 0.3 },
		iris = A.iris(a, "blue"),
		blush = true,
		whiskers = false,
	})
	-- the pale muzzle underside
	Kit.limb("MuzzleUnder", h.c + V(0, -0.24, 0.3), h.c + V(0, -0.26, 0.66), 0.13, 0.07, under, 0.7, UP)
	A.ears(h, { kind = "fox", len = 0.56, w = 0.36, at = 0.36, back = 6, c = b, inner = under, tip = sock })
	return t
end


local _v, _r, _j, _f, _u, _w = V, R, J, full, UP, FWD
return { plans = PLANS, forms = FORMS }
