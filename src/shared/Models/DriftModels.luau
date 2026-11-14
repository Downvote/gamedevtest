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
-- legs, arms, wings, fins, tail segments, eye stalks, pincers, tendrils and antennae). `animate(thing, time, mood, k,
-- squash)` turns each joint about its pivot for the moment and the mood (the joints' turns compose down the chain:
-- an ear on a head that nods), so a driftling breathes, looks about, blinks, twitches its ears, wags its tail and
-- walks on its own legs, winds up and lunges with its jaw open, recoils when hit and goes limp when knocked out.
-- Moods: "idle" | "walk" | "attack" (k: the blow's progress) | "hurt" | "cheer" | "ko".
-- The face parts (the thing's `face`: eyes, irises, shines, lids, the smile and the open mouth) are "Keep" parts and
-- blink by tucking in: the eye's parts go in and its lid comes out while it is shut; the smile goes in and the open
-- mouth comes out while the mouth is open.
local Kit = require(script.Parent.DriftKit)
local Blocks = require(script.Parent.Blocks)

local DriftModels = {}

export type Joint = Kit.Joint
export type Rig = Kit.Rig
export type Thing = Kit.Thing

local R = math.rad
local V = Vector3.new

------------------------------------------------------------------ the body plans
-- (Models/DriftPlansA..D, built with the kit: 20 plans, each a function of the body and accent colours)
local PLANS: { [string]: (b: string, a: string) -> Thing } = {}
for _, mod in { require(script.Parent.DriftPlansA), require(script.Parent.DriftPlansB), require(script.Parent.DriftPlansC), require(script.Parent.DriftPlansD) } do
	for shape, fn in mod do
		PLANS[shape] = fn
	end
end

function DriftModels.has(shape: string): boolean
	return PLANS[shape] ~= nil
end

-- A driftling of a body plan in its colours: `lod` "full" (close looks: the hatch scene, the portraits) or "world"
-- (the islands: fewer, bigger pieces), full when not given. `look` (its species': Data/Creatures) picks its eyes'
-- style and iris colour (DriftKit.eye) and the textures its body and accent colours wear (each part of that colour,
-- not the face, gets a "PixelTex" attribute: the pixel renderer patterns it, Render/DynTex).
export type Look = { eye: string?, iris: string?, tex: string?, tex2: string? }
function DriftModels.build(shape: string, body: string, accent: string, lod: string?, look: Look?): Thing
	local fn = PLANS[shape] or PLANS.blob
	Kit.setFull(lod ~= "world")
	Kit.setLook({ eye = look and look.eye, iris = look and look.iris, body = body, accent = accent })
	local ok, t = pcall(fn, body, accent)
	Kit.setFull(true)
	Kit.setLook(nil)
	if not ok then
		Kit.finish()
		error(t)
	end
	Kit.finish()
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
local function wave(x: number): number
	return math.sin(x)
end

-- The joints' turns for the moment, then every part's rest pose (times the squash `sc`), and the eyes' and mouth's
-- sizes. `time` in seconds (already offset per driftling), `k` 0..1 an attack's progress.
function DriftModels.animate(t: Thing, time: number, mood: string, k: number?, sc: Vector3)
	local rig = t.rig
	if rig == nil then
		return
	end
	local kk = math.clamp(k or 0, 0, 1)
	local fight = mood == "attack"
	local lunge = if fight then math.sin(kk * math.pi) else 0
	local windup = fight and kk < 0.02
	local cheer = mood == "cheer"
	local walk = mood == "walk"
	local hurt = mood == "hurt"
	local ko = mood == "ko"
	local excited = fight or cheer
	-- at work on the island (WorldView): pecking at a field, pushing a log, dipping for fish, waving at customers,
	-- napping at a nest, hopping at the Training Yard
	local peck = mood == "peck"
	local push = mood == "push"
	local dip = mood == "dip"
	local waving = mood == "wave"
	local nap = mood == "nap"
	local hopping = mood == "hop"
	local pk = if peck and (time % 3.2) < 1.9 then math.max(0, math.sin(time * 7)) ^ 2 else 0
	local dp = if dip then 0.5 + 0.5 * math.sin(time * 1.4) else 0
	local snap = dip and (time % 4) < 0.3
	local hopUp = if hopping then math.max(0, math.sin(time * 7)) else 0
	local gait = rig.gait
	local fly = gait == "fly"
	local step = time * 9 -- the walk's beat
	local blink = (time % 3.4) < 0.12
	-- now and then the head turns to look about, holds, and comes back
	local lookPhase = time % 6
	local look = if lookPhase < 1.6 then math.sin(lookPhase / 1.6 * math.pi) * (if math.floor(time / 6) % 2 == 0 then 1 else -1) else 0
	local world = rig.world
	for _, name in rig.order do
		local j = rig.joints[name]
		local side, ph = j.side, j.phase
		local rx, ry, rz = 0, 0, 0
		local tx, ty, tz = 0, 0, 0
		local kind = j.kind
		if kind == "body" then
			if fly then
				ty = 0.15 * wave(time * 2.2) + (if excited then 0.1 * wave(time * 9) else 0)
			else
				ty = 0.04 * wave(time * 2.4)
			end
			rz = R(2) * wave(time * 1.1)
			if walk then
				if gait == "hop" then
					local up = math.max(0, wave(step))
					ty += 0.3 * up
					rx = R(-10) * up
				elseif gait == "slither" then
					rz = R(6) * wave(step * 0.6)
					ty = 0
				else
					ty += 0.08 * math.abs(wave(step))
					rx = R(6)
				end
			end
			if fight then
				-- (a lunge: the body adds only a little)
				rx = if windup then R(-8) else R(8) * lunge
				tz = 0.15 * lunge
			elseif hurt then
				rx = R(-16)
				rz = R(6) * wave(time * 40)
			elseif cheer then
				rx = R(-8)
				ry = R(10) * wave(time * 10)
			elseif peck then
				rx = R(14) * pk
				ty -= 0.04 * pk
			elseif push then
				rx = R(12)
				ty += 0.04 * math.abs(wave(time * 4))
			elseif dip then
				rx = R(6) + R(10) * dp + (if snap then R(8) else 0)
			elseif waving then
				ty += 0.06 * math.max(0, wave(time * 6))
				ry = R(10) * wave(time * 1.5)
			elseif nap then
				ty = -0.12 + 0.03 * wave(time * 1.5)
				rx = R(4)
				rz = 0
			elseif hopping then
				ty += 0.35 * hopUp
				rx = R(-8) * hopUp
			end
		elseif kind == "head" or kind == "neck" then
			local amp = if kind == "neck" then 0.5 else 1
			ry = R(14) * look * amp
			rx = R(4) * wave(time * 1.3 + 0.5) * amp
			if walk then
				rx = R(6) * wave(step * 2) * amp
				ry = 0
			end
			if fight then
				rx = (if windup then R(-12) else R(12) * lunge) * amp
				ry = 0
				tz = 0.18 * lunge * amp
			elseif hurt then
				rx = R(-24) * amp
				ry = R(16) * amp
			elseif cheer then
				rx = R(-16) * amp
				rz = R(10) * wave(time * 10) * amp
				ry = 0
			elseif ko then
				rx = R(30) * amp
				rz = R(15) * amp
				ry = 0
			elseif peck then
				rx = R(38) * pk * amp
				ry = 0
			elseif dip then
				rx = (R(14) + R(20) * dp + (if snap then R(16) else 0)) * amp
				ry = 0
			elseif push then
				rx = R(10) * amp
				ry = 0
			elseif nap then
				rx = R(22) * amp
				ry = R(6) * amp
			elseif waving then
				rz = R(8) * wave(time * 3) * amp
			elseif hopping then
				rx = R(-10) * amp
				ry = 0
			end
		elseif kind == "jaw" then
			local open = 0
			if fight then
				open = if windup then R(10) else R(30) * lunge
			elseif cheer then
				open = R(14) + R(12) * wave(time * 10)
			elseif hurt then
				open = R(30)
			elseif ko then
				open = R(10)
			elseif peck then
				open = R(16) * pk
			elseif waving then
				open = R(14) * math.max(0, wave(time * 9))
			elseif snap then
				open = R(24)
			elseif nap then
				open = 0
			else
				-- a yawn now and then
				local yp = time % 9
				open = if yp < 0.7 then R(20) * math.sin(yp / 0.7 * math.pi) else 0
			end
			rx = open
		elseif kind == "ear" then
			local twitch = (time + side * 0.7) % 2.6 < 0.15
			local a = 0
			if hurt or ko then
				a = R(40)
			elseif cheer then
				a = R(10) * wave(time * 12)
			elseif twitch then
				a = R(18)
			elseif walk then
				a = R(6) * wave(step * 2)
			end
			rz = -side * a
		elseif kind == "arm" then
			local swing = R(6) * wave(time * 2 + side)
			if walk then
				swing = R(25) * wave(step + (if side > 0 then math.pi else 0))
			end
			rx = swing
			if fight then
				rx = if windup then R(30) else R(-110) * lunge
			elseif cheer then
				rx = R(-150)
				rz = -side * R(15) * wave(time * 10)
			elseif hurt then
				rx = R(-60) + R(10) * wave(time * 30)
				rz = -side * R(25)
			elseif ko then
				rx = R(-20)
			elseif waving then
				rx = if side > 0 then R(-140) + R(25) * wave(time * 10) else R(-20)
			elseif push then
				rx = R(-70)
			elseif peck then
				rx = R(-15) * pk
			elseif nap then
				rx = R(-30)
			elseif hopping then
				rx = R(-60) * hopUp
			end
		elseif kind == "leg" then
			if walk then
				if gait == "hop" then
					rx = R(-35) * math.max(0, wave(step))
				elseif gait == "scuttle" then
					local s = wave(step * 1.5 + ph * math.pi * 2)
					rz = side * R(14) * s
					ty = 0.06 * math.max(0, s)
				else
					local s = wave(step + ph * math.pi * 2)
					rx = R(28) * s
					ty = 0.08 * math.max(0, s)
				end
			elseif fly then
				rx = R(10) * wave(time * 3 + side)
			elseif cheer then
				ty = 0.1 * math.max(0, wave(time * 16 + ph * math.pi * 2))
			elseif push then
				-- (pacing on the spot, heaving)
				local s2 = wave(time * 4 + ph * math.pi * 2)
				rx = R(22) * s2
				ty = 0.05 * math.max(0, s2)
			elseif hopping then
				rx = R(-30) * hopUp
			elseif nap then
				rx = R(25)
			elseif fight then
				rx = R(-10) * lunge
			elseif ko then
				rx = R(20)
			end
		elseif kind == "tail" then
			local amp, f = R(10), 3
			if walk then
				amp, f = R(20), 9
			end
			if excited or waving or hopping then
				amp, f = R(30), 16
			elseif nap then
				amp, f = R(5), 1.2
			end
			-- (each segment adds to the one before: the later ones swing less, so the tip doesn't whip round)
			local seg = if ph >= 2 then 0.5 else 1
			ry = amp * seg * wave(time * f - ph * 0.8)
			if fight then
				rx = R(10) * lunge * seg
			elseif hurt then
				rx = R(-12) * seg
			elseif ko then
				ry = 0
				rx = R(-10)
			end
		elseif kind == "wing" then
			local flap
			local wseg = if ph >= 1 then 0.6 else 1 -- (the outer segment of a wing bends on a little more)
			if fly then
				flap = R(if excited then 40 else 28) * wseg * wave(time * (if excited then 20 else 11) - ph * 0.6)
			elseif excited then
				flap = R(35) * wseg * wave(time * 20 - ph * 0.6)
			elseif walk then
				flap = R(10) * wave(step)
			else
				flap = R(6) * wave(time * 3 - ph * 0.6)
			end
			if hurt then
				flap = R(35)
			elseif ko or nap then
				flap = R(-20)
			elseif waving then
				flap = R(25) * wseg * wave(time * 9 - ph * 0.6)
			end
			rz = side * flap
		elseif kind == "fin" then
			local a = if excited then R(25) * wave(time * 14) elseif walk then R(20) * wave(step) else R(6) * wave(time * 2.5)
			if side ~= 0 then
				rz = side * a
			else
				ry = a
			end
		elseif kind == "stalk" then
			rz = side * R(9) * wave(time * 2.3 + side)
			if hurt then
				rx = R(-30)
			elseif cheer then
				rz = side * R(18) * wave(time * 12)
			elseif ko then
				rx = R(40)
			end
		elseif kind == "pincer" then
			local open = R(14) * math.max(0, wave(time * 2.4 + side))
			if fight then
				open = R(50) * lunge
			elseif cheer then
				open = R(30) * math.abs(wave(time * 12))
			elseif hurt then
				open = R(30)
			end
			rx = -open
		elseif kind == "tendril" then
			local amp = (if excited then R(22) else R(12)) * (if ph % 1 > 0 then 0.6 else 1)
			rx = amp * wave(time * 3 + ph)
			rz = R(6) * wave(time * 2 + ph * 1.7)
			if ko then
				rx = R(30)
			end
		elseif kind == "antenna" then
			rx = R(10) * wave(time * 4 + side)
			if cheer then
				rx = R(20) * wave(time * 14 + side)
			elseif hurt then
				rx = R(25)
			end
		end
		local base = if j.parent then world[j.parent :: string] or CFrame.identity else CFrame.identity
		local pv = j.pivot
		world[name] = base * CFrame.new(pv.X + tx, pv.Y + ty, pv.Z + tz) * CFrame.fromEulerAnglesXYZ(rx, ry, rz) * CFrame.new(-pv)
	end
	local shut = blink or hurt or ko or nap
	local open = fight or hurt or cheer or waving or snap
	local face = t.face
	for name, p in t.parts do
		local r0 = t.baseRest[name]
		local fk = face[name]
		if fk then
			-- the kit's face parts (Models/DriftKit): each tucked in along its normal (its +X) while it is hidden
			local hide = if fk == "eye" then shut elseif fk == "lid" then not shut elseif fk == "open" then not open else open
			if hide then
				r0 = r0 * CFrame.new(t.tuck[name] or Vector3.new(-Kit.TUCK, 0, 0))
			end
			local w = world[rig.of[name] or "body"] or CFrame.identity
			local rr = w * r0
			t.rest[name] = CFrame.new(rr.Position * sc) * rr.Rotation
			continue
		end
		if shut and string.sub(name, 1, 5) == "Shine" then
			-- (a shut eye hides its shine: tucked behind it)
			r0 = r0 * CFrame.new(0, 0, -0.25)
		end
		local w = world[rig.of[name] or "body"] or CFrame.identity
		local rr = w * r0
		t.rest[name] = CFrame.new(rr.Position * sc) * rr.Rotation
		if name == "EyeL" or name == "EyeR" then
			local s = t.baseSize[name]
			local sz = V(s.X * sc.X, (if shut then 0.125 else s.Y) * sc.Y, s.Z * sc.Z)
			if p.Size ~= sz then
				p.Size = sz
			end
		elseif name == "Mouth" then
			local s = t.baseSize[name]
			local sz = V(s.X * sc.X, (if open then math.max(0.25, s.Y * 2.5) else s.Y) * sc.Y, s.Z * sc.Z)
			if p.Size ~= sz then
				p.Size = sz
			end
		end
	end
end

return DriftModels
