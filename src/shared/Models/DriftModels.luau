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

-- A driftling of a body plan in its colours: `lod` "full" (close looks: the hatch scene, the portraits), "world"
-- (fewer, bigger pieces) or "lite" (the islands: DriftModels.lite), full when not given. `look` (its species': Data/Creatures) picks its eyes'
-- style and iris colour (DriftKit.eye) and the textures its body and accent colours wear (each part of that colour,
-- not the face, gets a "PixelTex" attribute: the pixel renderer patterns it, Render/DynTex).
export type Look = { id: string?, eye: string?, iris: string?, tex: string?, tex2: string?, form: Form? }
local BLEND = 0.07 -- the body's blend radius, a share of the driftling's height
local BLEND_MIN = 0.07 -- studs: a solid thinner than this across (its middle size) is a detail, not blended
function DriftModels.build(shape: string, body: string, accent: string, lod: string?, look: Look?): Thing
	if lod == "lite" then
		return DriftModels.lite(DriftModels.build(shape, body, accent, "world", look))
	end
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

------------------------------------------------------------------ the islands' driftlings
-- The request (2026-11-22): "driftlings appear and disappear in and out ... you can make driftlings in the overworld
-- smaller, low polygonal and very easy to render, omitting most of their details"; then "they are low poly, but still
-- make them recognizable. for example, the dragon creatures have lost their wings and other recognizable details".
-- The islands' driftling is its "world" one cut down to what makes it its kind: the body's bulk (the pieces showing
-- at least LITE_CORE of it all: the body, the head), the biggest piece of each leg and arm, every main piece of a
-- feature joint (a wing, an ear, a tail, a fin, a pincer, an antenna, an eye stalk, a tendril, a shell, the neck:
-- LITE_FEATURE) and the signature pieces by name (horns, antlers, a beak, a mane, a crest, a sail, a shell's cap:
-- LITE_SIGN), then its other big pieces, in that order, at most LITE_MAX, each by how much of it shows (its two
-- biggest sizes multiplied, so a flat wing counts as much as it shows); its two eyes as plain dark ovals (light ones on
-- a dark head: the user's "the bats as well" came with a dark bat whose face was gone); nothing else
-- (no face to blink, no blended body, no textures, no smooth light, no skeleton), LITE_SCALE of the size.
-- Controllers/WorldView poses it whole (a waddle, a lean) in a few poses the pixel filter keeps pictures of, one set
-- for every driftling of its kind.
local LITE_MAX = 28
local LITE_CORE = 0.04 -- a piece showing this share of all of them is the body's bulk: always kept
local LITE_BIG = 0.015 -- a piece showing less than this share of all of them is a detail, unless it makes the kind
local LITE_SMALL = 0.003 -- a feature or signature piece showing less than this share is left out all the same
local LITE_PART = 0.25 -- of a feature joint's pieces, those showing at least this share of its biggest one
local LITE_FEATURE: { [string]: boolean } = { wing = true, ear = true, tail = true, fin = true, pincer = true, antenna = true, stalk = true, tendril = true, shell = true, neck = true }
local LITE_SIGN = { "Wing", "Membrane", "Horn", "Antler", "Tusk", "Trunk", "Beak", "Bill", "Crest", "Mane", "Ruff", "Frill", "Spade", "Sail", "Shell", "Cap", "Mantle", "Bell", "Dorsal", "HeadFin", "Crown", "Plume", "Spine", "Casque", "Hump", "Snout", "Muzzle", "Fluke", "Flipper", "Tentacle", "Lure", "Flame", "Crystal", "Icicle", "Bolt", "Club", "Sting", "Mandible", "Pincer", "Antenna", "Feather", "Topknot", "Ear", "Tail", "Fin", "Stalk", "Cloud", "Coral", "Sprout", "Leaf", "Toadstool", "Lantern", "Quill", "Collar", "Beard", "Forelock", "Paddle", "Shield", "Primary", "Coverts", "Web", "Shard", "Cere", "Comb", "Wool", "Tuft" }
local LITE_EYE_LUMA = 0.3 -- a head darker than this gets light eyes
DriftModels.LITE_SCALE = 0.7
function DriftModels.lite(t: Thing): Thing
	local rig = t.rig
	local function shows(p: BasePart): number
		local sz = p.Size
		local hi, lo = math.max(sz.X, sz.Y, sz.Z), math.min(sz.X, sz.Y, sz.Z)
		return hi * (sz.X + sz.Y + sz.Z - hi - lo)
	end
	local function sign(name: string): boolean
		for _, pre in LITE_SIGN do
			if string.sub(name, 1, #pre) == pre then
				return true
			end
		end
		return false
	end
	local area: { [string]: number } = {}
	local total = 0
	local byJoint: { [string]: number } = {}
	for name, p in t.parts do
		if t.face[name] == nil and p.Transparency < 0.95 and p:GetAttribute("PixelPaint") == nil and p:GetAttribute("PixelEye") == nil then
			local a = shows(p)
			area[name] = a
			total += a
			local j = if rig then rig.of[name] else nil
			if j then
				byJoint[j] = math.max(byJoint[j] or 0, a)
			end
		end
	end
	-- (each piece's rank: 0 the body's bulk, the pieces showing at least LITE_CORE of it all; 1 the biggest piece of
	-- each leg and arm; 2 the pieces that make the kind (a feature joint's, a signature name); 3 the other big ones)
	type Pick = { name: string, a: number, rank: number }
	local legTop: { [string]: string } = {}
	for name, a in area do
		local j = if rig then rig.of[name] else nil
		local jd = if rig and j then rig.joints[j] else nil
		if j and jd and (jd.kind == "leg" or jd.kind == "arm") then
			local cur = legTop[j]
			if cur == nil or area[cur] < a then
				legTop[j] = name
			end
		end
	end
	local isLegTop: { [string]: boolean } = {}
	for _, name in legTop do
		isLegTop[name] = true
	end
	local picked: { Pick } = {}
	for name, a in area do
		local p = t.parts[name]
		local j = if rig then rig.of[name] else nil
		local jd = if rig and j then rig.joints[j] else nil
		local feature = jd ~= nil and LITE_FEATURE[jd.kind] == true and a >= LITE_PART * (byJoint[j :: string] or 0)
		local rank = 4
		if a >= LITE_CORE * total and p.Material ~= Enum.Material.Neon then
			rank = 0
		elseif isLegTop[name] and a >= LITE_SMALL * total then
			rank = 1
		elseif (feature or sign(name)) and a >= LITE_SMALL * total then
			rank = 2
		elseif a >= LITE_BIG * total and p.Material ~= Enum.Material.Neon then
			rank = 3
		end
		if rank < 4 then
			local pk: Pick = { name = name, a = a, rank = rank }
			table.insert(picked, pk)
		end
	end
	-- (over LITE_MAX, the lowest ranks and the ones showing least go first)
	table.sort(picked, function(x, y): boolean
		if x.rank ~= y.rank then
			return x.rank < y.rank
		end
		if x.a ~= y.a then
			return x.a > y.a
		end
		return x.name < y.name
	end)
	local keep: { [string]: boolean } = {}
	for i, c in picked do
		if i > LITE_MAX then
			break
		end
		keep[c.name] = true
	end
	local eyes: { [string]: boolean } = {}
	for _, name in { "EyeL", "EyeR" } do
		local p = t.parts[name]
		if p and p.Transparency < 0.95 then
			keep[name] = true
			eyes[name] = true
		end
	end
	for name, p in t.parts do
		if not keep[name] then
			p:Destroy()
			t.parts[name], t.rest[name], t.sizes[name], t.baseRest[name], t.baseSize[name], t.colors[name] = nil, nil, nil, nil, nil, nil
		end
	end
	local k = DriftModels.LITE_SCALE
	-- (dark eyes, or light ones on a dark head, so a bat or a black dragon still has a face: the head is the kept piece
	-- whose middle is nearest the eye, dark below LITE_EYE_LUMA)
	local eyeColor = Blocks.color("black")
	for name in eyes do
		local at = t.baseRest[name].Position
		local best, bestD = nil :: BasePart?, math.huge
		for other, q in t.parts do
			if not eyes[other] then
				local d = (t.baseRest[other].Position - at).Magnitude
				if d < bestD then
					best, bestD = q, d
				end
			end
		end
		if best then
			local c = best.Color
			if 0.299 * c.R + 0.587 * c.G + 0.114 * c.B < LITE_EYE_LUMA then
				eyeColor = Blocks.color("cream")
			end
		end
		break
	end
	local dark = eyeColor
	for name, p in t.parts do
		for _, a in { "PixelBlend", "PixelTex", "PixelOwn", "PixelEye", "PixelEyeIris", "PixelEyeDark", "PixelEyeLid", "PixelEyeSide", "Keep" } do
			p:SetAttribute(a, nil)
		end
		local r = t.baseRest[name]
		if eyes[name] then
			-- (a plain dark oval, set a little further out of the head than the painted one: made smaller with the rest,
			-- its bulge would fall under the pixel filter's depth bias and the head would hide it)
			p.Color = dark
			t.colors[name] = dark
			r = r * CFrame.new(0, 0, 0.06)
		end
		local sz = t.baseSize[name] * k
		sz = Vector3.new(math.max(0.05, sz.X), math.max(0.05, sz.Y), math.max(0.05, sz.Z))
		r = CFrame.new(r.Position * k) * r.Rotation
		p.Size = sz
		t.baseSize[name], t.sizes[name], t.baseRest[name], t.rest[name] = sz, sz, r, r
	end
	t.model:SetAttribute("PixelSmooth", nil)
	t.model.Name = "Micro_lite_" .. string.sub(t.kind, 7)
	t.face, t.tuck, t.rig = {}, {}, nil
	t.h, t.r = t.h * k, t.r * k
	t.lod = "lite"
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
