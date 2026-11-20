--!strict
-- Everything a founder wears, as parts on the founder's standing rig (docs/ARCHITECTURE.md 6; GAME_DESIGN 14.1). Pure:
-- Vector3, CFrame and palette keys. Two kinds of piece meet here:
--   * this game's own (Models/CosmeticModels, drawn on the founder already), recoloured by the look's tint for their
--     slot: the colour most of the piece is in takes the tint, the second most its accent (Data/Looks.tinted);
--   * Random Bakery's (the request of 2026-11-20: "Port the entire character customization menu from the bakery game to
--     this game, such accessory colors and other features, along with the accessories it has"): Models/AccessoryModels
--     and Models/AccessoryBasics draw them in the bakery's bigger body, and this fits each bone's parts onto the
--     founder: a uniform 0.75 about the bone's anchor (the bakery's head middle (0, 3.5, 0) to the founder's
--     (0, 3.125, -0.1), its torso (0, 1.75, 0) to (0, 1.875, 0), its fists (+-1, 1.25, 0) to (+-0.8125, 1.39, 0)),
--     turns kept. Their loops of moves (Api.anim) are fitted the same way.
-- The look's apron and bangs come through here too (the bakery's, in its body space), and the piece in the hand is
-- turned about the fist by the look's turn.
--   WearModels.build(look) -> Built          the parts of everything worn, the apron and the bangs
--   WearModels.piece(id, look?) -> { Spec }  one piece's parts alone (the cosmetic pictures; `look` for the hair)
--   WearModels.covers(id) -> string?         what a hat hides of the hair ("top", "hood")
--   WearModels.top(look) -> Recolor?         a top's colours for the shirt under it, after the look's tint
-- A Spec's `bone`: "head" (moves with the head), "body" (the torso), "hand" (the right forearm), "handL" (the left);
-- `moves`: its loop (rig space, applied before its rest CFrame, 7 frames a second: CharacterModels.posePose).
local AccessoryModels = require(script.Parent.AccessoryModels)
local AccessoryBasics = require(script.Parent.AccessoryBasics)
local CosmeticModels = require(script.Parent.CosmeticModels)
local Cosmetics = require(script.Parent.Parent.Data.Cosmetics)
local Looks = require(script.Parent.Parent.Data.Looks)

local WearModels = {}

export type Spec = CosmeticModels.Spec

export type Built = {
	specs: { Spec },
	headHat: boolean, -- the hat is the whole head (the Pumpkin Head, Headless): no head, face or hair under it
	hatBottom: number?, -- a covering bakery hat's lower edge (standing rig y): the hair cap stops at it
	covers: string?, -- what the hat hides of the hair
	apron: boolean, -- an apron lies over the shirt's front (its buttons and buckle go under it)
	bangs: boolean, -- bangs in place of the hair's own fringe
}

local K = 0.75
type Bone = { from: Vector3, to: Vector3, name: string }
local HEAD, ROOT, ARM_R, ARM_L = 1, 2, 3, 4
local BONES: { [number]: Bone } = {
	[HEAD] = { from = Vector3.new(0, 3.5, 0), to = Vector3.new(0, 3.125, -0.1), name = "head" },
	[ROOT] = { from = Vector3.new(0, 1.75, 0), to = Vector3.new(0, 1.875, 0), name = "body" },
	[ARM_R] = { from = Vector3.new(1, 1.25, 0), to = Vector3.new(0.8125, 1.39, 0), name = "hand" },
	[ARM_L] = { from = Vector3.new(-1, 1.25, 0), to = Vector3.new(-0.8125, 1.39, 0), name = "handL" },
}

-- a part in the bakery's body space
type Def = { bone: number, size: Vector3, cf: CFrame, color: string, shape: string?, neon: boolean?, moves: { CFrame }? }

-- Two loops one after the other (`outer` after `inner`, frame by frame), as long as both together repeat (at most 48
-- frames).
local function loopAfter(outer: { CFrame }, inner: { CFrame }): { CFrame }
	local a, b = #outer, #inner
	local n = a
	while n % b ~= 0 and n < 48 do
		n += a
	end
	local out: { CFrame } = table.create(n)
	for f = 1, n do
		out[f] = outer[(f - 1) % a + 1] * inner[(f - 1) % b + 1]
	end
	return out
end

local function collector(): (AccessoryModels.Api, { Def })
	local defs: { Def } = {}
	local api: AccessoryModels.Api = {
		add = function(bone: number, sx: number, sy: number, sz: number, x: number, y: number, z: number, color: string, rot: CFrame?, shape: string?, _name: string?)
			table.insert(defs, { bone = bone, size = Vector3.new(sx, sy, sz), cf = CFrame.new(x, y, z) * (rot or CFrame.identity), color = color, shape = shape })
		end,
		ball = function(bone: number, d: number, x: number, y: number, z: number, color: string, _name: string?)
			table.insert(defs, { bone = bone, size = Vector3.new(d, d, d), cf = CFrame.new(x, y, z), color = color, shape = "Ball" })
		end,
		cyl = function(bone: number, d: number, h: number, x: number, y: number, z: number, color: string, _name: string?)
			-- (a standing cylinder: Roblox's run along X)
			table.insert(defs, { bone = bone, size = Vector3.new(h, d, d), cf = CFrame.new(x, y, z) * CFrame.Angles(0, 0, math.pi / 2), color = color, shape = "Cylinder" })
		end,
		glow = function()
			local d = defs[#defs]
			if d then
				d.neon = true
			end
		end,
		count = function(): number
			return #defs
		end,
		anim = function(from: number, frames: { CFrame })
			for i = from + 1, #defs do
				local d = defs[i]
				d.moves = if d.moves then loopAfter(frames, d.moves) else frames
			end
		end,
		HEAD = HEAD,
		ROOT = ROOT,
		ARM_R = ARM_R,
		ARM_L = ARM_L,
	}
	return api, defs
end

-- Whether bakery-space point `p` is inside the torso, the head or the right arm (where a moving part hides between its
-- frames).
local function hiddenAt(p: Vector3): boolean
	local x, y, z = p.X, p.Y, p.Z
	return (math.abs(x) < 0.75 and y > 1 and y < 2.5 and math.abs(z) < 0.5)
		or (math.abs(x) < 1 and y > 2.5 and y < 4.5 and math.abs(z) < 1)
		or (x > 0.75 and x < 1.25 and y > 1.375 and y < 2.375 and math.abs(z) < 0.25)
end

-- Turns the defs after `from` (a held piece) `deg` degrees forward about grip frame G's x axis, their loops with them;
-- a frame that hides a part inside the body keeps it hidden where it was. A piece that would reach below the floor
-- (a long ribbon turned back) turns only as far as it clears it.
local function turnHeld(defs: { Def }, from: number, G: CFrame, deg: number)
	local T = CFrame.identity
	for _, k in { 1, 0.75, 0.5, 0.25, 0 } do
		T = G * CFrame.Angles(math.rad(deg * k), 0, 0) * G:Inverse()
		local low = math.huge
		for i = from + 1, #defs do
			local d = defs[i]
			local cf = T * d.cf
			local _, y, _, _, _, _, r10, r11, r12 = cf:GetComponents()
			local s = d.size
			low = math.min(low, y - (math.abs(r10) * s.X + math.abs(r11) * s.Y + math.abs(r12) * s.Z) / 2)
		end
		if low >= 0 then
			break
		end
	end
	local Ti = T:Inverse()
	for i = from + 1, #defs do
		local d = defs[i]
		local cf = d.cf
		local moves = d.moves
		if moves then
			local out: { CFrame } = table.create(#moves)
			for f, m in moves do
				out[f] = if hiddenAt((m * cf).Position) then m * Ti else T * m * Ti
			end
			d.moves = out
		end
		d.cf = T * cf
	end
end

-- A bakery def as a founder spec: its bone's similarity (scale K about the bone's anchor, moved to the founder's).
local function fit(d: Def, name: string): Spec
	local b = BONES[d.bone] or BONES[HEAD]
	local p = d.cf.Position
	local moves: { CFrame }? = nil
	if d.moves then
		local out: { CFrame } = table.create(#d.moves)
		for f, m in d.moves do
			-- m' = A m A^-1 for A: x -> to + K (x - from)
			local R = m.Rotation
			local t = b.to - R * b.to + (R * b.from + m.Position - b.from) * K
			out[f] = CFrame.new(t) * R
		end
		moves = out
	end
	local rot = d.cf.Rotation
	return {
		name = name,
		size = d.size * K,
		at = b.to + (p - b.from) * K,
		color = d.color,
		shape = d.shape :: any,
		rot = if rot == CFrame.identity then nil else rot,
		bone = b.name,
		neon = d.neon,
		moves = moves,
	}
end

-- This game's own piece in tint `t`: the colour most of it is in (by volume) takes the tint, the second its accent (a
-- top: the colours it gives the shirt, `main` and `second`).
local function recolor(list: { Spec }, t: string?, main: string?, second: string?): { Spec }
	if t == nil then
		return list
	end
	if main == nil then
		local vol: { [string]: number } = {}
		for _, sp in list do
			vol[sp.color] = (vol[sp.color] or 0) + sp.size.X * sp.size.Y * sp.size.Z
		end
		local mv, sv = -1, -1
		for c, v in vol do
			if v > mv then
				second, sv = main, mv
				main, mv = c, v
			elseif v > sv then
				second, sv = c, v
			end
		end
	end
	if main == nil then
		return list
	end
	local c2, a2 = Looks.tinted(main, second or main, t)
	local out: { Spec } = table.create(#list)
	for i, sp in list do
		local col = if sp.color == main then c2 elseif sp.color == second then a2 else sp.color
		if col == sp.color then
			out[i] = sp
		else
			local copy = table.clone(sp)
			copy.color = col
			out[i] = copy
		end
	end
	return out
end

-- The founder's colours a bakery piece reads (its ctx).
local function ctxOf(look: { [string]: any }, tint: string?, head: boolean): AccessoryBasics.Ctx
	local style = Looks.styles[look.style] or "short"
	return {
		hair = Looks.hair[look.hair] or "hair_brown",
		bald = style == "bald",
		skin = Looks.skin[look.skin] or "skin1",
		head = head,
		top = Looks.shirt[look.shirt] or "blue",
		tint = tint,
	}
end

-- Draws bakery piece `pc` into the collector; returns whether it drew. Its colours after the tint (Data/Looks.tinted);
-- a piece with no colour of its own (cat ears, the moustache) is in the hair colour.
local function drawBakery(api: AccessoryModels.Api, pc: Cosmetics.Piece, ctx: AccessoryBasics.Ctx): boolean
	local kind = pc.kind
	if kind == nil then
		return false
	end
	local t = if pc.rainbow then nil else ctx.tint
	local c, a = Looks.tinted(pc.color or ctx.hair, pc.accent or "white", t)
	if string.sub(kind, 1, 2) == "b_" then
		return AccessoryBasics.build(api, pc.slot, kind, c, a, ctx)
	end
	return AccessoryModels.build(api, pc.slot, kind, c, a, { hair = ctx.hair, bald = ctx.bald, skin = ctx.skin, head = ctx.head })
end

local HAND = CosmeticModels.HAND

-- The parts of everything `look` wears, its apron and its bangs.
function WearModels.build(look: { [string]: any }): Built
	local specs: { Spec } = {}
	local hat = if type(look.hat) == "string" then Cosmetics.byId[look.hat] else nil
	local headHat = hat ~= nil and hat.head == true
	local covers = if hat then (if hat.kind then hat.covers else CosmeticModels.covers(hat.id)) else nil
	local hatBottom: number? = nil
	if hat and hat.kind then
		local b = hat.bottom or AccessoryBasics.BOTTOM[hat.kind]
		if b then
			hatBottom = 3.125 + (b - 3.5) * K
		end
	end
	local api, defs = collector()
	local function flush(prefix: string)
		for i, d in defs do
			table.insert(specs, fit(d, prefix .. "_B" .. i))
		end
		table.clear(defs)
	end
	for _, slot in Looks.worn do
		local id = look[slot]
		if type(id) ~= "string" or id == "" then
			continue
		end
		local pc = Cosmetics.byId[id]
		if pc == nil or (headHat and slot == "face") then
			continue
		end
		local tint = Looks.tintOf(look, slot)
		local deg = if slot == "hand" then Looks.turnOf(look) else 0
		if pc.kind then
			if drawBakery(api, pc, ctxOf(look, tint, headHat)) and deg ~= 0 then
				turnHeld(defs, 0, AccessoryModels.grip(pc.kind), deg)
			end
			flush(id)
		else
			local tr = if slot == "top" then CosmeticModels.top(id) else nil
			local list = recolor(CosmeticModels.parts(id), tint, if tr then tr.torso else nil, if tr then tr.trim else nil)
			if deg ~= 0 then
				-- turned about the fist, forward
				local T = CFrame.new(HAND) * CFrame.Angles(math.rad(deg), 0, 0) * CFrame.new(-HAND)
				local turned: { Spec } = table.create(#list)
				for i, sp in list do
					local cf = T * CFrame.new(sp.at) * (sp.rot or CFrame.identity)
					local copy = table.clone(sp)
					copy.at = cf.Position
					copy.rot = cf.Rotation
					turned[i] = copy
				end
				list = turned
			end
			for _, sp in list do
				table.insert(specs, sp)
			end
		end
	end
	-- the apron
	local ap = Looks.aprons[if type(look.apron) == "number" then look.apron else 1]
	local apron = false
	if ap and ap.pattern ~= "none" then
		AccessoryBasics.apron(api, ap, Looks.tintOf(look, "apron"))
		flush("Apron")
		apron = ap.pattern ~= "cloak"
	end
	-- the bangs, from the hair cap's front edge or a covering hat's lower edge (the bakery's head space)
	local bang = Looks.bangs[if type(look.bangs) == "number" then look.bangs else 1]
	local style = Looks.styles[look.style] or "short"
	local bangs = false
	if bang and bang.id ~= "auto" and style ~= "bald" and not headHat and covers ~= "hood" then
		bangs = true
		local color = Looks.hair[look.hair] or "hair_brown"
		local h2 = if type(look.hair2) == "number" and look.hair2 > 0 then Looks.hair[look.hair2] else nil
		local top = if hat and hat.kind and hatBottom then (hat.bottom or AccessoryBasics.BOTTOM[hat.kind :: string] or 4.4) else 4.4
		if bang.id ~= "none" then
			AccessoryBasics.bangs(api, bang.id, color, h2 or color, top)
			flush("Bangs")
		end
	end
	return { specs = specs, headHat = headHat, hatBottom = hatBottom, covers = covers, apron = apron, bangs = bangs }
end

-- One piece's parts alone (its own colours), as worn by `look` (default: the first of everything).
function WearModels.piece(id: string, look: { [string]: any }?): { Spec }
	local l: { [string]: any } = look or { skin = 1, hair = 1, style = 1, shirt = 1 }
	local pc = Cosmetics.byId[id]
	if pc == nil then
		return {}
	end
	if pc.kind == nil then
		return CosmeticModels.parts(id)
	end
	local api, defs = collector()
	drawBakery(api, pc, ctxOf(l, nil, pc.head == true))
	local out: { Spec } = {}
	for i, d in defs do
		out[i] = fit(d, id .. "_B" .. i)
	end
	return out
end

function WearModels.top(look: { [string]: any }): CosmeticModels.Recolor?
	local id = look.top
	local tr = if type(id) == "string" and id ~= "" then CosmeticModels.top(id) else nil
	local t = Looks.tintOf(look, "top")
	if tr == nil or t == nil then
		return tr
	end
	local main = tr.torso or tr.arms
	if main == nil then
		return tr
	end
	local c, a = Looks.tinted(main, tr.trim or main, t)
	local function swap(k: string?): string?
		return if k == main then c elseif k ~= nil and k == tr.trim then a else k
	end
	return { torso = swap(tr.torso), arms = swap(tr.arms), trim = swap(tr.trim), hide = tr.hide }
end

function WearModels.covers(id: string): string?
	local pc = Cosmetics.byId[id]
	if pc and pc.kind then
		return pc.covers
	end
	return CosmeticModels.covers(id)
end

return WearModels
