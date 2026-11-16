-- tests/specs/DriftMotion.spec.luau: the driftlings' motion (Models/DriftMotion; the request of 2026-11-14, "please use
-- bones and rigging to make more realistic and detailed movement. follow and use as many animation principles when
-- animating as well"): every ease goes from 0 to 1, a keyed curve meets its keys and loops close, a jump crouches
-- before it leaves the ground (anticipation), stretches leaving and squashes landing and spends longer in the air than
-- on the ground (timing), a walk squashes at each step's contact, a hit squashes hard and wobbles back, ears twitch one
-- at a time, and every mood gives every bone a finite pose. Since the request of 2026-11-16 ("Pose and animate them in
-- ways that make them look natural and lively and bring out what they are more"): every body plan has its own manner
-- (a style: carriage, idle acts, walk and cheer), its acts start and end at rest and never jump, they play one at a
-- time every few seconds and differently for each driftling, the styles differ, a planted foot sweeps back as it
-- walks and stays on the ground as the body pitches, and every style stays finite and in range over a long run.
local T = require("../TestKit")
local Motion = require("../../build/luautest/shared/Models/DriftMotion")

local function finite(x: number): boolean
	return x == x and x > -1e6 and x < 1e6
end

-- the 37 body plans (Models/DriftPlans*) and the gait each is built with
local PLANS: { [string]: string } = {
	pup = "quad", cat = "quad", bear = "quad", otter = "quad", monkey = "biped", yeti = "biped", deer = "quad",
	ram = "quad", elephant = "quad", griffin = "quad", drake = "quad", bun = "hop", mole = "quad", hedgehog = "quad",
	armadillo = "quad", turtle = "quad", golem = "biped", lizard = "quad", frog = "hop", crab = "scuttle",
	beetle = "scuttle", snail = "slither", wyrm = "slither", seal = "slither", fish = "fly", ray = "fly",
	seahorse = "fly", octo = "fly", jelly = "fly", shroom = "biped", sprite = "fly", bird = "biped", owl = "biped",
	penguin = "biped", duck = "biped", bat = "fly", moth = "fly",
}
-- the styles a species' form may name instead of its plan's, and the gait that species is built with
local EXTRA: { [string]: string } = {
	lion = "quad", horse = "quad", goat = "quad", chameleon = "quad", croc = "quad", axolotl = "quad",
	seaturtle = "quad", seaotter = "biped", whale = "fly", heron = "biped", skybird = "fly", toad = "hop",
	hermit = "scuttle", bee = "fly", treant = "biped",
}
local KINDS = { "body", "head", "neck", "jaw", "ear", "arm", "leg", "tail", "wing", "fin", "stalk", "pincer", "tendril", "antenna" }
-- a few bones of every kind: sides, phases (a leg's place in the stride and fore or hind, a segment down a chain) and
-- pivots off the root
local BONES: { { any } } = {}
for _, kind in KINDS do
	for _, side in { -1, 0, 1 } do
		for _, ph in { 0, 0.5, 1.5, 2 } do
			table.insert(BONES, { kind, side, ph, 0.3 * side, if ph < 0.25 then 0.4 else -0.4 })
		end
	end
end
local function pose(o: any, b: { any }): (number, number, number, number, number, number, number)
	return Motion.bone(o, b[1], b[2], b[3], b[4], b[5])
end
local function styleGait(name: string): string
	return PLANS[name] or EXTRA[name] or "quad"
end

return function()
	T.it("each ease starts at 0 and ends at 1", function()
		for _, id in { Motion.LINEAR, Motion.SMOOTH, Motion.OUT, Motion.IN, Motion.BACK, Motion.HOLD } do
			T.near(Motion.ease(id, 0), 0, 1e-9, "start " .. id)
			T.near(Motion.ease(id, 1), 1, 1e-9, "end " .. id)
		end
		T.truthy(Motion.ease(Motion.OUT, 0.25) > Motion.ease(Motion.IN, 0.25) + 0.3, "out starts fast, in starts slow")
		local over = 0
		for i = 1, 99 do
			over = math.max(over, Motion.ease(Motion.BACK, i / 100))
		end
		T.truthy(over > 1.02, "back-out goes past the mark")
		T.near(Motion.ease(Motion.SMOOTH, 0.5), 0.5, 1e-9, "smooth is even")
	end)

	T.it("a keyed curve meets its keys, and the looping ones close", function()
		local J = Motion.JUMP
		for name, keys in { jty = J.ty, jsq = J.sq, jrx = J.rx, jleg = J.leg, look = Motion.LOOK, weight = Motion.WEIGHT, peck = Motion.PECK, dip = Motion.DIP } do
			T.eq(keys[1][1], 0, name .. " starts at 0")
			T.eq(keys[#keys][1], 1, name .. " ends at 1")
			for i, k in keys do
				T.near(Motion.track(keys, k[1]), k[2], 1e-9, name .. " key " .. i)
				if i > 1 then
					T.truthy(k[1] >= keys[i - 1][1], name .. " in order")
				end
			end
			T.near(Motion.track(keys, 0), Motion.track(keys, 1), 1e-9, name .. " loops")
		end
	end)

	T.it("a jump: anticipation, stretch, squash, and longer in the air", function()
		local J = Motion.JUMP
		local lowest, crouchAt, stretch, stretchAt, peak, landSq, air = 1e9, 0, 0, 0, 0, 1e9, 0
		for i = 0, 199 do
			local u = i / 200
			local ty, sq = Motion.track(J.ty, u), Motion.track(J.sq, u)
			if u < 0.3 and ty < lowest then
				lowest, crouchAt = ty, u
			end
			if u < 0.4 and sq > stretch then
				stretch, stretchAt = sq, u
			end
			peak = math.max(peak, ty)
			if u > 0.7 then
				landSq = math.min(landSq, sq)
			end
			if ty > 0.02 then
				air += 1
			end
		end
		T.truthy(lowest < -0.05 and Motion.track(J.sq, crouchAt) < 0.9, "it crouches, squashed, before it jumps")
		T.truthy(crouchAt < stretchAt, "the crouch comes before the stretch")
		T.truthy(stretch > 1.1, "it stretches leaving the ground")
		T.truthy(landSq < 0.85, "it squashes landing")
		T.truthy(peak > 0.4, "it gets off the ground")
		T.truthy(air > 100, "more time in the air than on the ground")
	end)

	T.it("every mood gives every bone a finite pose", function()
		local kinds = { "body", "head", "neck", "jaw", "ear", "arm", "leg", "tail", "wing", "fin", "stalk", "pincer", "tendril", "antenna", "nothing" }
		local o = Motion.newProg()
		for _, gait in { "quad", "biped", "hop", "scuttle", "slither", "fly" } do
			for _, mood in { "idle", "walk", "cheer", "hop", "attack", "hurt", "ko", "peck", "push", "dip", "wave", "nap", "rest", "hooray", "unknown" } do
				for i = 0, 30 do
					local t = i * 0.37
					Motion.program(mood, t, t, (i % 11) / 10, gait, 1, 3.3, o)
					for _, kind in kinds do
						for _, side in { -1, 0, 1 } do
							local rx, ry, rz, tx, ty, tz, sq = Motion.bone(o, kind, side, (i % 3) * 0.5)
							for _, x in { rx, ry, rz, tx, ty, tz, sq } do
								T.truthy(finite(x), string.format("%s %s %s finite", gait, mood, kind))
							end
							T.truthy(sq > 0.5 and sq < 1.6, string.format("%s %s %s stretch in range", gait, mood, kind))
						end
					end
				end
			end
		end
	end)

	T.it("a walk walks: no hop, a foot always on the ground, the body rising a little over the planted leg", function()
		-- (the request of 2026-11-15: "most creatures seem to walk around by bouncing instead of actually walking")
		local o = Motion.newProg()
		local legs = {
			biped = { { -1, 0 }, { 1, 0.5 } },
			quad = { { -1, 0 }, { 1, 0.5 }, { -1, 0.5 }, { 1, 0 } },
			hop = { { -1, 0 }, { 1, 0 } }, -- (a hopper's legs are built in step: the walk has them take turns)
		}
		for gait, set in legs do
			local lo, hi, sqLo, sqHi, airborne = 9, -9, 9, 0, 0
			for i = 0, 200 do
				Motion.program("walk", i / 200, 1, 0, gait, 1, 0, o)
				lo, hi = math.min(lo, o.bty), math.max(hi, o.bty)
				sqLo, sqHi = math.min(sqLo, o.bsq), math.max(sqHi, o.bsq)
				local planted = false
				for _, l in set do
					local _, _, _, _, ty = Motion.bone(o, "leg", l[1], l[2])
					if ty <= 1e-6 then
						planted = true
					end
				end
				if not planted then
					airborne += 1
				end
			end
			T.truthy(lo >= 0 and hi <= 0.06 and hi > 0.01, string.format("%s: the body %.3f .. %.3f studs up", gait, lo, hi))
			T.truthy(sqLo > 0.96 and sqHi < 1.04, string.format("%s: squash %.3f .. %.3f", gait, sqLo, sqHi))
			T.eq(airborne, 0, gait .. ": frames with no foot on the ground")
		end
	end)

	T.it("a hooray jumps once, then holds the happy pose", function()
		-- (the request of 2026-11-14: "make the pet jump only once instead of a few times after hatching")
		local o = Motion.newProg()
		for _, gait in { "biped", "quad", "hop" } do
			local jumps, up = 0, false
			for i = 0, 300 do
				local age = i / 100
				Motion.program("hooray", 7 + age, age, 0, gait, 1, 2.5, o)
				local high = o.bty > 0.2
				if high and not up then
					jumps += 1
				end
				up = high
			end
			T.eq(jumps, 1, gait .. ": one jump in three seconds")
			T.truthy(o.bty == 0 and o.bsq == 1 and o.open and o.arm < -2, gait .. ": landed, arms up, mouth open")
		end
	end)

	T.it("a hit squashes hard at once and wobbles back", function()
		local o = Motion.newProg()
		Motion.program("hurt", 5, 0, 0, "quad", 1, 0, o)
		T.truthy(o.bsq < 0.85, "squashed on the hit")
		local passed = false
		for i = 1, 30 do
			Motion.program("hurt", 5, i * 0.01, 0, "quad", 1, 0, o)
			passed = passed or o.bsq > 1.02
		end
		T.truthy(passed, "it springs back past its size (a wobble)")
		Motion.program("hurt", 5, 1.5, 0, "quad", 1, 0, o)
		T.near(o.bsq, 1, 0.01, "settled")
		T.truthy(o.shut and o.open, "eyes shut, mouth open")
	end)

	T.it("ears twitch one at a time, blinks are short, a cheer opens the mouth, a nap shuts the eyes", function()
		local o = Motion.newProg()
		local together, apart, shutFrames = 0, 0, 0
		for i = 0, 1199 do
			local t = i / 60
			Motion.program("idle", t, t, 0, "quad", 1, 0, o)
			local _, _, l = Motion.bone(o, "ear", -1, 0)
			local _, _, r = Motion.bone(o, "ear", 1, 0)
			local lt, rt = math.abs(l) > 0.05, math.abs(r) > 0.05
			if lt and rt then
				together += 1
			elseif lt or rt then
				apart += 1
			end
			if o.shut then
				shutFrames += 1
			end
		end
		T.truthy(apart > 20 and together < apart / 3, string.format("twitches apart %d, together %d", apart, together))
		T.truthy(shutFrames > 5 and shutFrames < 160, string.format("blinks: %d of 1200 frames shut", shutFrames))
		Motion.program("cheer", 2, 2, 0, "biped", 1, 0, o)
		T.truthy(o.open and o.arm < -2, "a cheer: mouth open, arms up")
		Motion.program("nap", 2, 2, 0, "biped", 1, 0, o)
		T.truthy(o.shut, "a nap: eyes shut")
	end)

	T.it("every body plan has its own style, and every style's acts exist and fit its time", function()
		local n = 0
		for plan in PLANS do
			n += 1
			T.truthy(Motion.STYLE[plan] ~= nil and Motion.STYLE[plan] ~= Motion.STYLE.default, plan .. " has its own style")
		end
		T.eq(n, 37, "body plans")
		for name in EXTRA do
			T.truthy(Motion.STYLE[name] ~= nil, name .. " is a style")
		end
		for name, S in Motion.STYLE do
			local distinct = {}
			for _, a in S.acts do
				local A = Motion.ACTS[a]
				T.truthy(A ~= nil, name .. ": act " .. a .. " exists")
				if A then
					T.truthy(A.dur > 0.5 and A.dur <= S.every - 0.8, string.format("%s: %s (%.1f s) fits in %.1f s", name, a, A.dur, S.every))
				end
				distinct[a] = true
			end
			local k = 0
			for _ in distinct do
				k += 1
			end
			T.truthy(k >= (if name == "default" then 2 else 3), name .. ": three acts or more")
			T.truthy(S.every >= 3 and S.every <= 8, name .. ": an act every 3 to 8 s")
			T.truthy(S.breathT > 0.4 and S.hoverF > 0 and S.wingF > 0, name .. ": its cycles have a speed")
		end
		-- (an unknown style gets the old manner)
		T.eq(Motion.style("nothing"), Motion.STYLE.default, "unknown style")
		T.eq(Motion.style(nil), Motion.STYLE.default, "no style")
	end)

	T.it("each idle act starts and ends at rest and never jumps from frame to frame", function()
		for name, A in Motion.ACTS do
			-- (played as the first style that lists it plays it, on that style's gait)
			local styleName = "default"
			for sn, S in Motion.STYLE do
				if table.find(S.acts, name) then
					styleName = sn
					break
				end
			end
			local gait = styleGait(styleName)
			for _, side in { -1, 1 } do
				local rest = Motion.newProg()
				rest.gait, rest.plant = gait, if gait == "fly" then 0 else 1
				for _, u in { 0, 1 } do
					local o = table.clone(rest)
					Motion.act(o, name, u, 3.7, side, styleName)
					T.truthy(o.shut == rest.shut, string.format("%s at %d: eyes as at rest", name, u))
					for _, b in BONES do
						local a1, a2, a3, a4, a5, a6, a7 = pose(rest, b)
						local b1, b2, b3, b4, b5, b6, b7 = pose(o, b)
						local d = math.max(math.abs(a1 - b1), math.abs(a2 - b2), math.abs(a3 - b3), math.abs(a4 - b4), math.abs(a5 - b5), math.abs(a6 - b6), math.abs(a7 - b7))
						T.truthy(d < 1e-6, string.format("%s at u %d: %s %d %.1f at rest (off %.2g)", name, u, b[1], b[2], b[3], d))
					end
				end
				-- through it at 60 frames a second: every bone moves less than a third of a radian (or stud) a frame
				local frames = math.ceil(A.dur * 60)
				local last: { { number } } = {}
				local worst, at = 0, ""
				for f = 0, frames do
					local o = table.clone(rest)
					o.t = f / 60
					Motion.act(o, name, f / frames, f / 60, side, styleName)
					for i, b in BONES do
						local r = { pose(o, b) }
						local l = last[i]
						if l then
							for j = 1, 7 do
								local d = math.abs(r[j] - l[j])
								if d > worst then
									worst, at = d, string.format("%s %d %.1f", b[1], b[2], b[3])
								end
							end
						end
						last[i] = r
					end
				end
				T.truthy(worst < 0.34, string.format("%s: the most a bone moves in a frame %.3f (%s)", name, worst, at))
			end
		end
	end)

	T.it("a planted foot stays on the ground as the body pitches and rises", function()
		-- (the hip's drop from the body's pitch about its pivot, dz studs along it, and its rise, against the leg's shift)
		local o = Motion.newProg()
		for _, act in { "bow", "stretch", "pushup", "situp", "graze", "curl" } do
			for i = 1, 9 do
				local r = Motion.newProg()
				r.gait, r.plant = "quad", 1
				o = r
				Motion.act(o, act, i / 10, 2, 1, "pup")
				for _, leg in { { -1, 0, 0.42 }, { 1, 0, -0.42 } } do
					local _, _, _, _, ty = Motion.bone(o, "leg", leg[1], leg[2], 0.2 * leg[1], leg[3])
					local hip = o.bty - leg[3] * math.sin(o.brx)
					local fore = (leg[1] < 0) == (leg[2] < 0.25)
					if not (fore and o.free > 0) then
						T.near(ty + hip, 0, 1e-9, string.format("%s at %.1f: foot %d on the ground", act, i / 10, leg[1]))
					end
				end
			end
		end
	end)

	T.it("an idle plays one act at a time every few seconds, and no two driftlings together", function()
		for plan in PLANS do
			local S = Motion.STYLE[plan]
			local starts, seen, last = 0, {}, nil
			local kinds = 0
			for i = 0, 2400 do
				local name, u = Motion.actAt(plan, i * 0.05, 2.3, 1)
				if name and name ~= last then
					starts += 1
					if not seen[name] then
						seen[name] = true
						kinds += 1
					end
				end
				T.truthy(u >= 0 and u <= 1, plan .. ": progress in 0..1")
				last = name
			end
			local want = 120 / S.every
			T.truthy(starts >= want * 0.6 and starts <= want * 1.05, string.format("%s: %d acts in 120 s (one every %.1f s)", plan, starts, S.every))
			T.truthy(kinds >= math.min(3, #S.acts), string.format("%s: %d different acts", plan, kinds))
			-- two driftlings of the same kind, side by side: rarely the same act at the same moment
			local same = 0
			for i = 0, 2400 do
				local a, ua = Motion.actAt(plan, i * 0.05, 1.3, 1)
				local b, ub = Motion.actAt(plan, i * 0.05, 4.7, 1)
				if a and a == b and math.abs(ua - ub) < 0.1 then
					same += 1
				end
			end
			T.truthy(same < 2400 * 0.03, string.format("%s: in step %d of 2400 frames", plan, same))
		end
	end)

	T.it("the styles differ: no two plans stand, act and move alike", function()
		local sig: { [string]: string } = {}
		for plan in PLANS do
			local S = Motion.STYLE[plan] :: any
			local bits = { table.concat(S.acts, ","), S.cheer }
			local keys = {}
			for k, v in S do
				if type(v) == "number" then
					table.insert(keys, k)
				end
			end
			table.sort(keys)
			for _, k in keys do
				table.insert(bits, string.format("%s=%.3f", k, S[k]))
			end
			sig[plan] = table.concat(bits, ";")
		end
		for a, sa in sig do
			for b, sb in sig do
				if a < b then
					T.truthy(sa ~= sb, a .. " and " .. b .. " differ")
				end
			end
		end
		-- and in motion: a dog's tail and a cat's over the same half minute
		local o = Motion.newProg()
		local diff = 0
		for i = 0, 600 do
			local t = i * 0.05
			Motion.program("idle", t, t, 0, "quad", 1, 2, o, "pup")
			local _, dog = Motion.bone(o, "tail", 0, 1)
			local dogUp = Motion.bone(o, "tail", 0, 1)
			Motion.program("idle", t, t, 0, "quad", 1, 2, o, "cat")
			local _, cat = Motion.bone(o, "tail", 0, 1)
			local catUp = Motion.bone(o, "tail", 0, 1)
			diff += math.abs(dog - cat) + math.abs(dogUp - catUp)
		end
		T.truthy(diff / 601 > 0.1, string.format("a dog's tail and a cat's: %.3f apart", diff / 601))
	end)

	T.it("every style on every gait stays finite and in range over a long run", function()
		local o = Motion.newProg()
		local gaits = { "quad", "biped", "hop", "scuttle", "slither", "fly" }
		for name in Motion.STYLE do
			for gi, gait in gaits do
				for _, mood in { "idle", "walk", "cheer", "hooray", "hop", "hurt", "nap" } do
					local n = if mood == "idle" then (if gait == styleGait(name) then 160 else 24) else 6
					for i = 1, n do
						local t = (i * 3.71 + gi * 0.53) % 600
						Motion.program(mood, t, (i * 0.37) % 3, 0, gait, 0.82 + (i % 5) * 0.09, (i * 1.7) % 10, o, name)
						for _, b in BONES do
							local rx, ry, rz, tx, ty, tz, sq = pose(o, b)
							local ok = finite(rx) and finite(ry) and finite(rz) and finite(tx) and finite(ty) and finite(tz) and finite(sq)
							ok = ok and math.abs(rx) < 3.2 and math.abs(ry) < 3.2 and math.abs(rz) < 3.2
							ok = ok and math.abs(tx) < 0.6 and math.abs(ty) < 1 and math.abs(tz) < 0.6 and sq > 0.5 and sq < 1.6
							if not ok then
								error(string.format("%s %s %s t %.2f: %s %d %.1f -> %.2f %.2f %.2f %.2f %.2f %.2f %.2f", name, gait, mood, t, b[1], b[2], b[3], rx, ry, rz, tx, ty, tz, sq))
							end
						end
					end
				end
			end
		end
	end)

	T.it("a walk's planted foot sweeps back under the body, and every walker keeps a foot down", function()
		-- (+rx swings a foot behind its hip: a planted foot goes from in front to behind as the body passes over it)
		local o = Motion.newProg()
		local lastRx, sweeps, wrong = nil :: number?, 0, 0
		for i = 0, 300 do
			Motion.program("walk", i / 300, 1, 0, "quad", 1, 0, o)
			local rx, _, _, _, ty = Motion.bone(o, "leg", -1, 0)
			if lastRx and ty <= 1e-9 then
				if rx > lastRx then
					sweeps += 1
				elseif rx < lastRx - 1e-9 then
					wrong += 1
				end
			end
			lastRx = if ty <= 1e-9 then rx else nil
		end
		T.truthy(sweeps > 100 and wrong == 0, string.format("planted: %d frames sweeping back, %d forward", sweeps, wrong))
		local legs = {
			biped = { { -1, 0 }, { 1, 0.5 } },
			quad = { { -1, 0 }, { 1, 0.5 }, { -1, 0.5 }, { 1, 0 } },
			hop = { { -1, 0 }, { 1, 0 } },
		}
		local all = {}
		for k, v in PLANS do
			all[k] = v
		end
		for k, v in EXTRA do
			all[k] = v
		end
		for name, gait in all do
			local set = legs[gait]
			if set then
				local lo, hi, sqLo, sqHi, airborne = 9, -9, 9, 0, 0
				for i = 0, 200 do
					Motion.program("walk", i / 200, 1, 0, gait, 1, 0, o, name)
					lo, hi = math.min(lo, o.bty), math.max(hi, o.bty)
					sqLo, sqHi = math.min(sqLo, o.bsq), math.max(sqHi, o.bsq)
					local planted = false
					for _, l in set do
						local _, _, _, _, ty = Motion.bone(o, "leg", l[1], l[2])
						if ty <= 1e-6 then
							planted = true
						end
					end
					if not planted then
						airborne += 1
					end
				end
				T.truthy(lo >= 0 and hi <= 0.06 and hi > 0.01, string.format("%s: the body %.3f .. %.3f studs up", name, lo, hi))
				T.truthy(sqLo > 0.96 and sqHi < 1.04, string.format("%s: squash %.3f .. %.3f", name, sqLo, sqHi))
				T.eq(airborne, 0, name .. ": frames with no foot on the ground")
			end
		end
	end)

	T.it("every style's hooray jumps once, then holds its happy pose", function()
		local o = Motion.newProg()
		for name in Motion.STYLE do
			local gait = styleGait(name)
			if gait ~= "fly" then
				local jumps, up = 0, false
				for i = 0, 300 do
					local age = i / 100
					Motion.program("hooray", 7 + age, age, 0, gait, 1, 2.5, o, name)
					local high = o.bty > 0.2
					if high and not up then
						jumps += 1
					end
					up = high
				end
				T.eq(jumps, 1, name .. ": one jump in three seconds")
				T.truthy(o.bty == 0 and o.open, name .. ": landed, mouth open")
			end
		end
	end)
end
