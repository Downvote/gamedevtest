--!strict
-- The driftlings in 3D (GAME_DESIGN 6; docs/ARCHITECTURE.md 6). Roblox module (client: MicroModels.driftling builds
-- them for the islands, the islets' stages and the boat).
--
-- The requests (2026-11-11): "alot of the creatures are just simple shapes meshed together. can they be more detailed
-- and look more like the animals /creatures that they are referencing?"; "add more expressive idle and other
-- animations to the creatures, the whole mesh seems to move as one throughout all their animations. you can make
-- different moving parts for creatures to allow for more expressiveness".
--
-- The request (2026-11-13): "The creatures look blocky and unrealistic. Look at the cakes in the bakery game to
-- reference how detailed they should be". The body plans are built with Models/DriftKit (round pieces on a fine grid,
-- tubes, pillows, discs, proper eyes; a "full" and a lighter "world" level of detail) in Models/DriftPlans*.
--
-- Each body plan (Data/Creatures `shape`) is built from plain parts (Models/Blocks: palette colours, no meshes),
-- facing +Z with its feet on the ground, in its species' body and accent colours, on a small
-- skeleton: joints with a pivot and a parent (the body, then the head on it, the jaw and the ears on the head, the
-- legs, arms, wings, fins, tail segments, eye stalks, pincers, tendrils and antennae). Since the request of 2026-11-14
-- ("please use bones and rigging to make more realistic and detailed movement. follow and use as many animation
-- principles when animating as well") the joints are the bones of a rig (Models/DriftRig: each with a length and a
-- direction, the parts skinned to them with weights so joints bend smoothly, the body squashing and stretching,
-- springs on the ears, tails and the like) moved by keyed poses that ease (Models/DriftMotion: anticipation, follow
-- through, arcs and the rest), blended from mood to mood.
-- The face parts (the thing's `face`: eyes, irises, shines, lids, the smile and the open mouth) are "Keep" parts and
-- blink by tucking in: the eye's parts go in and its lid comes out while it is shut; the smile goes in and the open
-- mouth comes out while the mouth is open.
local Kit = require(script.Parent.DriftKit)
local Blocks = require(script.Parent.Blocks)
local DriftRig = require(script.Parent.DriftRig)

local DriftModels = {}

export type Joint = Kit.Joint
export type Rig = Kit.Rig
export type Thing = Kit.Thing


------------------------------------------------------------------ the body plans
-- (Models/DriftPlansA..F since the request of 2026-11-15, "currently, all of them are modelled using blobs, which is
-- unnatural": 37 plans sculpted from smooth solids with Models/DriftAnatomy, each a function of the body and accent
-- colours and the species' form, and the forms that make each species of a plan its own)
type Form = { [string]: any }
local PLANS: { [string]: (b: string, a: string, form: Form?) -> Thing } = {}
local FORMS: { [string]: Form } = {}
for _, mod in { require(script.Parent.DriftPlansA), require(script.Parent.DriftPlansB), require(script.Parent.DriftPlansC), require(script.Parent.DriftPlansD), require(script.Parent.DriftPlansE), require(script.Parent.DriftPlansF) } do
	for shape, fn in mod.plans do
		PLANS[shape] = fn
	end
	for id, f in mod.forms do
		FORMS[id] = f
	end
end

function DriftModels.has(shape: string): boolean
	return PLANS[shape] ~= nil
end

-- A driftling of a body plan in its colours: `lod` "full" (close looks: the hatch scene, the portraits) or "world"
-- (the islands: fewer, bigger pieces), full when not given. `look` (its species': Data/Creatures) picks its eyes'
-- style and iris colour (DriftKit.eye) and the textures its body and accent colours wear (each part of that colour,
-- not the face, gets a "PixelTex" attribute: the pixel renderer patterns it, Render/DynTex).
export type Look = { id: string?, eye: string?, iris: string?, tex: string?, tex2: string?, form: Form? }
local BLEND = 0.07 -- the body's blend radius, a share of the driftling's height
local BLEND_MIN = 0.07 -- studs: a solid thinner than this across (its middle size) is a detail, not blended
function DriftModels.build(shape: string, body: string, accent: string, lod: string?, look: Look?): Thing
	local fn = PLANS[shape] or PLANS.armadillo
	Kit.setFull(lod ~= "world")
	Kit.setLook({ eye = look and look.eye, iris = look and look.iris, body = body, accent = accent, tex = look and look.tex, tex2 = look and look.tex2 })
	-- (its species' own form: Data/Creatures' when it gives one, else the plan module's for its id)
	local form = if look then (look.form or (if look.id then FORMS[look.id] else nil)) else nil
	local ok, t = pcall(fn, body, accent, form)
	Kit.setFull(true)
	Kit.setLook(nil)
	if not ok then
		Kit.finish()
		error(t)
	end
	Kit.finish()
	-- (its manner for the motion, Models/DriftMotion: the plan's own, or its form's)
	if t.rig then
		t.rig.style = if form and type(form.style) == "string" then form.style else shape
	end
	-- The body drawn as one blended surface (Render/Raster.drawBlend; the request of 2026-11-16: "You should not be able
	-- to see the shapes that the creatures consist of ... make them all look like one connected mesh instead of clearly
	-- different simple shapes put together"): every smooth solid of the body is a member but the face, the lit bits and
	-- the thin details (whiskers, lashes, claws, teeth: under BLEND_MIN across), which stay crisp and are drawn first.
	-- The blend radius is BLEND times the driftling's height, kept as a share of each part's largest size so it scales
	-- with the model.
	local k = BLEND * t.h
	for name, p in t.parts do
		local sh = p:GetAttribute("PixelShape")
		if t.face[name] == nil and p.Material ~= Enum.Material.Neon and p:GetAttribute("PixelEye") == nil and p:GetAttribute("PixelOwn") == nil and (sh == "Ell" or sh == "Egg" or sh == "Cone") then
			local s = p.Size
			local hi, lo = math.max(s.X, s.Y, s.Z), math.min(s.X, s.Y, s.Z)
			local mid = s.X + s.Y + s.Z - hi - lo
			if mid >= BLEND_MIN and hi > 0 then
				p:SetAttribute("PixelBlend", k / hi)
			end
		end
	end
	local tex, tex2 = look and look.tex, look and look.tex2
	if tex or tex2 then
		local cb, ca = Blocks.color(body), Blocks.color(accent)
		for name, p in t.parts do
			if t.face[name] == nil and p.Material ~= Enum.Material.Neon then
				if tex and p.Color == cb then
					p:SetAttribute("PixelTex", tex)
				elseif tex2 and p.Color == ca then
					p:SetAttribute("PixelTex", tex2)
				end
			end
		end
	end
	return t
end

------------------------------------------------------------------ animate
-- Pose it for the moment on its skeleton (Models/DriftRig: bones, skin weights, squash and stretch, springs; the moods
-- from Models/DriftMotion). `time` in seconds (its own clock, offset per driftling: keep it running smoothly, the
-- springs and the blends between moods need it), `k` 0..1 an action's progress, `sc` MicroModels.scale's squash.
function DriftModels.animate(t: Thing, time: number, mood: string, k: number?, sc: Vector3)
	if t.rig == nil then
		return
	end
	DriftRig.animate(t, time, mood, k, sc)
end

return DriftModels
