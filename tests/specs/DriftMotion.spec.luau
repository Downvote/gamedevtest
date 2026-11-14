-- tests/specs/DriftMotion.spec.luau: the driftlings' motion (Models/DriftMotion; the request of 2026-11-14, "please use
-- bones and rigging to make more realistic and detailed movement. follow and use as many animation principles when
-- animating as well"): every ease goes from 0 to 1, a keyed curve meets its keys and loops close, a jump crouches
-- before it leaves the ground (anticipation), stretches leaving and squashes landing and spends longer in the air than
-- on the ground (timing), a walk squashes at each step's contact, a hit squashes hard and wobbles back, ears twitch one
-- at a time, and every mood gives every bone a finite pose.
local T = require("../TestKit")
local Motion = require("../../build/luautest/shared/Models/DriftMotion")

local function finite(x: number): boolean
	return x == x and x > -1e6 and x < 1e6
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
		for name, keys in { jty = J.ty, jsq = J.sq, jrx = J.rx, jleg = J.leg, step = Motion.STEP_SQ, look = Motion.LOOK, weight = Motion.WEIGHT, peck = Motion.PECK, dip = Motion.DIP } do
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

	T.it("a walk squashes at each contact and stretches between", function()
		local o = Motion.newProg()
		local lo, hi = 9, 0
		for i = 0, 140 do
			Motion.program("walk", i / 200, 1, 0, "biped", 1, 0, o)
			lo, hi = math.min(lo, o.bsq), math.max(hi, o.bsq)
		end
		T.truthy(lo < 0.95 and hi > 1.02, string.format("squash %.2f .. %.2f", lo, hi))
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
end
