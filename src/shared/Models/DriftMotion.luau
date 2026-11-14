--!strict
-- The driftlings' motion (GAME_DESIGN 6; docs/ARCHITECTURE.md 6): what each bone of a driftling's skeleton
-- (Models/DriftRig) does at a moment, in each mood. Pure maths, no instances (tests/specs/DriftMotion.spec.luau).
--
-- The request (2026-11-14): "right now, the models simply move by rotating or moving parts of the mesh around. please
-- use bones and rigging to make more realistic and detailed movement. follow and use as many animation principles
-- when animating as well."
--
-- A mood is a "program": once a frame it works out a handful of shared values from keyed curves (a key is a time, a
-- value and how the curve eases into it), and each bone reads its pose from them: three turns (rx, ry, rz, radians,
-- about its pivot), a shift (tx, ty, tz, studs) and a stretch along the bone (sq: 1 as built, over 1 longer and
-- thinner, under 1 squashed and wider, its volume kept). Where the twelve principles are:
--   squash and stretch: the body squashes before a jump and on landing and stretches as it leaves the ground and as
--     it falls (`JUMP`), squashes at each step's contact and stretches between (`STEP_SQ`), breathes in and out,
--     squashes on a hit and wobbles back, stretches into a peck or a lunge; ears stretch as they perk up.
--   anticipation: a crouch before every jump, a lean back before a lunge, the head dipping the other way before it
--     turns to look about, rising before a peck, a breath in before a yawn.
--   staging: one clear action at a time; the head turns toward what it looks at, the arms stay out of the face.
--   straight ahead and pose to pose: the keyed poses here (pose to pose) and the rig's springs (straight ahead:
--     Models/DriftRig works out the ears, tails, antennae, tendrils, stalks, fins and wing tips frame by frame).
--   follow through and overlapping action: the head's nod comes a beat after the body's step, the arms swing a beat
--     after the legs, the tail's segments wave each a little later; the springs carry on after the body stops.
--   slow in and slow out: every key eases (`EASE`), cycles are sines.
--   arcs: every bone turns about its pivot, a jump rises and falls on a curve, a lunge goes forward and down.
--   secondary action: blinks and double blinks, ear twitches, breathing, a tail sway while it pecks or naps.
--   timing: a bigger driftling moves slower (`tempo`), a jump spends longer in the air than on the ground, a peck
--     strikes fast and comes back slowly.
--   exaggeration: a cheer jumps higher and squashes harder than a hop; a hit squashes hard.
--   solid drawing: the weight shifts onto the planted foot, the hips twist with the stride, the head keeps level
--     against the body's roll.
--   appeal: no twins (left and right a little out of step, each driftling's own phase from its seed), a head tilt
--     with a look.
--   Motion.program(mood, t, age, k, gait, tempo, seed, out) -> Prog   (t seconds, age: seconds in this mood, k an
--     action's progress 0..1, gait "quad" | "biped" | "hop" | "scuttle" | "slither" | "fly")
--   Motion.bone(prog, kind, side, phase) -> (rx, ry, rz, tx, ty, tz, sq)
--   Motion.ease(id, x), Motion.track(keys, u), Motion.JUMP and the other key sets (the specs read them)
local Motion = {}

local PI = math.pi
local TAU = 2 * math.pi
local sin, cos, exp, max, min, abs, floor = math.sin, math.cos, math.exp, math.max, math.min, math.abs, math.floor

------------------------------------------------------------------ easing
-- 0 linear, 1 smooth (in and out), 2 out (fast start, slow end), 3 in (slow start, fast end), 4 back-out (past the
-- mark and back), 5 hold (the old value until the key)
local LINEAR, SMOOTH, OUT, IN, BACK, HOLD = 0, 1, 2, 3, 4, 5
Motion.LINEAR, Motion.SMOOTH, Motion.OUT, Motion.IN, Motion.BACK, Motion.HOLD = LINEAR, SMOOTH, OUT, IN, BACK, HOLD

function Motion.ease(id: number, x: number): number
	x = if x < 0 then 0 elseif x > 1 then 1 else x
	if id == SMOOTH then
		return x * x * (3 - 2 * x)
	elseif id == OUT then
		local y = 1 - x
		return 1 - y * y * y
	elseif id == IN then
		return x * x * x
	elseif id == BACK then
		local y = x - 1
		return 1 + y * y * (2.7 * y + 1.7)
	elseif id == HOLD then
		return if x >= 1 then 1 else 0
	end
	return x
end
local ease = Motion.ease

-- A keyed curve at u (0..1): keys { {u, value, ease}, ... } in order of u, the first at 0 and the last at 1; each key's
-- ease says how the curve comes into it from the key before.
export type Keys = { { number } }
function Motion.track(keys: Keys, u: number): number
	local n = #keys
	if u <= keys[1][1] then
		return keys[1][2]
	end
	for i = 2, n do
		local b = keys[i]
		if u <= b[1] then
			local a = keys[i - 1]
			local span = b[1] - a[1]
			local x = if span > 0 then (u - a[1]) / span else 1
			return a[2] + (b[2] - a[2]) * ease(b[3] or SMOOTH, x)
		end
	end
	return keys[n][2]
end
local track = Motion.track

local function frac(x: number): number
	return x - floor(x)
end

------------------------------------------------------------------ the key sets
-- One jump (a hop, a cheer, the Training Yard): crouch (anticipation, squashed), push off (stretched, fast), the arc
-- (slowing at the top), the fall (stretching again), the landing (squashed hard) and the settle (a little past and
-- back). Heights are for a jump of size 1 (studs), stretch as is.
Motion.JUMP = {
	ty = { { 0, 0 }, { 0.14, -0.1, OUT }, { 0.26, 0.3, IN }, { 0.44, 0.44, OUT }, { 0.64, 0.14, IN }, { 0.74, 0, IN }, { 0.82, -0.08, OUT }, { 1, 0, SMOOTH } },
	sq = { { 0, 1 }, { 0.14, 0.82, OUT }, { 0.24, 1.16, IN }, { 0.44, 1, OUT }, { 0.66, 1.07, IN }, { 0.78, 0.8, OUT }, { 0.9, 1.04, OUT }, { 1, 1, SMOOTH } },
	-- (the body: leaning into the crouch, back as it pushes off, forward again to land)
	rx = { { 0, 0 }, { 0.14, 0.12, OUT }, { 0.26, -0.16, IN }, { 0.48, -0.04, SMOOTH }, { 0.74, 0.1, IN }, { 0.84, 0.14, OUT }, { 1, 0, SMOOTH } },
	-- (the legs: folding into the crouch, kicking back to push off, tucked in the air, reaching to land, bending)
	leg = { { 0, 0 }, { 0.14, 0.55, OUT }, { 0.26, -0.5, IN }, { 0.44, 0.3, OUT }, { 0.7, -0.18, SMOOTH }, { 0.82, 0.42, OUT }, { 1, 0, SMOOTH } },
}
-- A step's squash: squashed at the foot's contact, stretched at the top of the step.
Motion.STEP_SQ = { { 0, 0.9 }, { 0.14, 1, OUT }, { 0.5, 1.05, SMOOTH }, { 0.86, 1, SMOOTH }, { 1, 0.9, IN } }
-- A look about (over 6 s): a small turn the other way first (anticipation), the turn past the mark and back, a hold,
-- then home.
Motion.LOOK = { { 0, 0 }, { 0.035, -0.1, OUT }, { 0.12, 1.08, OUT }, { 0.17, 1, SMOOTH }, { 0.38, 1, SMOOTH }, { 0.5, 0, SMOOTH }, { 1, 0 } }
-- The weight shifted from foot to foot (over 8 s).
Motion.WEIGHT = { { 0, 0 }, { 0.12, 1, SMOOTH }, { 0.45, 1, SMOOTH }, { 0.6, -1, SMOOTH }, { 0.92, -1, SMOOTH }, { 1, 0, SMOOTH } }
-- A yawn (over 1.8 s): breathing in with the head back, the jaw opening wide, holding, closing, a little shake.
Motion.YAWN = {
	jaw = { { 0, 0 }, { 0.25, 0.05, SMOOTH }, { 0.45, 0.42, OUT }, { 0.74, 0.38, SMOOTH }, { 0.9, 0, IN }, { 1, 0 } },
	head = { { 0, 0 }, { 0.3, -0.18, SMOOTH }, { 0.75, -0.2, SMOOTH }, { 0.9, 0.05, OUT }, { 1, 0, SMOOTH } },
	sq = { { 0, 0 }, { 0.4, 0.05, SMOOTH }, { 0.8, 0.04, SMOOTH }, { 0.93, -0.03, OUT }, { 1, 0, SMOOTH } },
}
-- A peck (over 1.7 s): up and back first, a fast strike down, a slow return, a smaller second peck.
Motion.PECK = { { 0, 0 }, { 0.18, -0.2, OUT }, { 0.26, 0.72, IN }, { 0.34, 0.64, SMOOTH }, { 0.55, 0.04, OUT }, { 0.62, 0, SMOOTH }, { 0.68, 0.46, IN }, { 0.74, 0.4, SMOOTH }, { 0.9, 0, OUT }, { 1, 0 } }
-- A dip for fish (over 3 s): leaning down slowly, holding, a snap, back up.
Motion.DIP = { { 0, 0 }, { 0.35, 1, SMOOTH }, { 0.55, 1, SMOOTH }, { 0.62, 1.28, IN }, { 0.7, 1, OUT }, { 0.9, 0, SMOOTH }, { 1, 0 } }
-- A lunge (over its k): the wind-up back and squashed, the strike forward and stretched, past the mark, home.
Motion.LUNGE = {
	rx = { { 0, 0 }, { 0.3, -0.22, OUT }, { 0.42, 0.26, IN }, { 0.56, 0.18, OUT }, { 1, 0, SMOOTH } },
	sq = { { 0, 1 }, { 0.3, 0.85, OUT }, { 0.42, 1.15, IN }, { 0.56, 0.95, OUT }, { 0.7, 1.02, SMOOTH }, { 1, 1, SMOOTH } },
	tz = { { 0, 0 }, { 0.3, -0.12, OUT }, { 0.42, 0.32, IN }, { 0.6, 0.24, SMOOTH }, { 1, 0, SMOOTH } },
	head = { { 0, 0 }, { 0.32, -0.26, OUT }, { 0.46, 0.3, IN }, { 0.62, 0.16, OUT }, { 1, 0, SMOOTH } },
	arm = { { 0, 0 }, { 0.3, 0.6, OUT }, { 0.42, -1.9, IN }, { 0.6, -1.7, SMOOTH }, { 1, 0, SMOOTH } },
}
-- An ear's twitch (over 0.3 s): flicked fast, settling slowly.
Motion.TWITCH = { { 0, 0 }, { 0.22, 1, OUT }, { 1, 0, SMOOTH } }

------------------------------------------------------------------ the programs
export type Prog = {
	mood: string,
	gait: string,
	t: number,
	-- the body (the root bone): the whole creature, its stretch squashing all of it from the ground up
	brx: number,
	bry: number,
	brz: number,
	btx: number,
	bty: number,
	btz: number,
	bsq: number,
	-- the head (a neck takes half), the jaw
	hrx: number,
	hry: number,
	hrz: number,
	htz: number,
	hsq: number,
	jaw: number,
	-- ears: a turn out (+ droops, - perks) and a twitch's strength; arms; legs; tails; wings; the small parts
	ear: number,
	earSq: number,
	twitch: number,
	armMode: number, -- 0 swaying, 1 swinging with the stride, 2 raised, 3 one waving, 4 forward, 5 striking
	arm: number, -- the arms' turn (radians, about X: - raises them forward and up)
	armZ: number,
	legMode: number, -- 0 still, 1 walking, 2 jumping, 3 scuttling, 4 pacing, 5 folded, 6 dangling
	leg: number,
	u: number, -- the stride's or jump's phase (0..1)
	tailAmp: number,
	tailF: number,
	tailRx: number,
	tailCurl: number,
	wingAmp: number,
	wingF: number,
	wingRest: number,
	finAmp: number,
	finF: number,
	small: number, -- stalks, antennae, tendrils, pincers: how lively (1 calm .. 2 excited)
	pincer: number,
	droop: number, -- small parts droop (hurt, out cold)
	shut: boolean, -- the eyes shut (a blink, asleep, hurt)
	open: boolean, -- the mouth open (the face's open mouth shows)
}

function Motion.newProg(): Prog
	return {
		mood = "idle",
		gait = "quad",
		t = 0,
		brx = 0,
		bry = 0,
		brz = 0,
		btx = 0,
		bty = 0,
		btz = 0,
		bsq = 1,
		hrx = 0,
		hry = 0,
		hrz = 0,
		htz = 0,
		hsq = 1,
		jaw = 0,
		ear = 0,
		earSq = 1,
		twitch = 1,
		armMode = 0,
		arm = 0,
		armZ = 0,
		legMode = 0,
		leg = 0,
		u = 0,
		tailAmp = 0.17,
		tailF = 2.2,
		tailRx = 0,
		tailCurl = 0,
		wingAmp = 0.1,
		wingF = 3,
		wingRest = 0,
		finAmp = 0.1,
		finF = 2.5,
		small = 1,
		pincer = 0,
		droop = 0,
		shut = false,
		open = false,
	}
end

-- A blink every few seconds (by the seed), now and then a double one.
local function blinking(t: number, seed: number): boolean
	local b = (t + seed * 1.7) % 3.6
	if b < 0.11 then
		return true
	end
	local d = (t + seed * 2.3) % 13
	return d > 0.24 and d < 0.35
end

local function reset(o: Prog, mood: string, gait: string, t: number)
	o.mood, o.gait, o.t = mood, gait, t
	o.brx, o.bry, o.brz, o.btx, o.bty, o.btz, o.bsq = 0, 0, 0, 0, 0, 0, 1
	o.hrx, o.hry, o.hrz, o.htz, o.hsq, o.jaw = 0, 0, 0, 0, 1, 0
	o.ear, o.earSq, o.twitch = 0, 1, 1
	o.armMode, o.arm, o.armZ = 0, 0, 0
	o.legMode, o.leg, o.u = 0, 0, 0
	o.tailAmp, o.tailF, o.tailRx, o.tailCurl = 0.17, 2.2, 0, 0
	o.wingAmp, o.wingF, o.wingRest = 0.1, 3, 0
	o.finAmp, o.finF = 0.1, 2.5
	o.small, o.pincer, o.droop = 1, 0, 0
	o.shut, o.open = false, false
end

-- How far a body plan's body pitches: a long body (four legs, a serpent) tips its head a long way for a small turn.
local PITCH: { [string]: number } = { quad = 0.45, slither = 0.3, scuttle = 0.6, fly = 0.6 }

-- A jump at phase u of size `size` (studs at its top, about) and stretch `squash` (how far from 1).
local function jump(o: Prog, u: number, size: number, squash: number)
	local J = Motion.JUMP
	o.u = u
	o.bty = track(J.ty, u) * size
	o.bsq = 1 + (track(J.sq, u) - 1) * squash
	o.brx = track(J.rx, u) * (PITCH[o.gait] or 1)
	o.legMode = 2
	o.leg = track(J.leg, u)
	-- (the head comes a beat after the body: overlapping action)
	local lag = frac(u - 0.07)
	o.hrx = -0.6 * (track(J.rx, lag) - o.brx) + 0.06 * (track(J.sq, lag) - 1) * 4
	-- (ears perk going up and the springs fling them on the way down)
	o.earSq = 1 + 0.06 * max(0, track(J.sq, u) - 1) * 6
end

-- the breath: in and out every 3 s, the body a little taller breathing in
local function breathe(o: Prog, t: number, depth: number)
	local b = sin(TAU * t / 3.1)
	o.bsq *= 1 + 0.022 * depth * b
	o.bty += 0.012 * depth * b
end

-- Work out a mood's shared values at time t into `out`. Moods: "idle", "walk", "cheer", "hop", "attack" (k), "hurt"
-- and "ko" (by age), and the work moods "peck", "push", "dip", "wave", "nap".
function Motion.program(mood: string, t: number, age: number, k: number, gait: string, tempo: number, seed: number, out: Prog): Prog
	local o = out
	reset(o, mood, gait, t)
	local fly = gait == "fly"
	local tt = t * tempo
	o.shut = blinking(t, seed)
	if mood == "walk" then
		-- one stride (two steps) every 0.7 s at tempo 1
		local u = frac(tt * 9 / TAU + seed * 0.13)
		o.u = u
		o.tailAmp, o.tailF = 0.3, 9 * tempo
		o.armMode = 1
		o.wingAmp, o.wingF = 0.16, 9 * tempo
		o.finAmp, o.finF = 0.3, 9 * tempo
		if gait == "hop" then
			jump(o, u, 0.6, 0.4)
		elseif gait == "slither" then
			o.brz = 0.1 * sin(TAU * u)
			o.hry = -0.5 * 0.1 * sin(TAU * (u - 0.08))
			o.tailAmp, o.tailF = 0.42, 9 * tempo
			o.legMode = 1
		elseif gait == "scuttle" then
			o.legMode = 3
			o.bty = 0.03 * abs(sin(TAU * u * 3))
			o.brz = 0.03 * sin(TAU * u * 1.5)
		elseif fly then
			o.bty = 0.15 * sin(TAU * t * 0.4) + 0.05 * sin(t * 12 * tempo - 0.9)
			o.brx = 0.14
			o.wingAmp, o.wingF = 0.7, 12 * tempo
			o.legMode = 6
			o.leg = 0.25
		else
			-- a bouncy walk: a little hop each step, squashed as the foot lands, the weight on the planted foot,
			-- the hips twisting with the stride, the head nodding a beat after the step and keeping level
			local s = frac(2 * u)
			local hop = 4 * s * (1 - s)
			o.bty = 0.2 * hop
			o.bsq = track(Motion.STEP_SQ, s)
			o.brz = 0.05 * sin(TAU * u)
			o.bry = 0.035 * sin(TAU * u)
			o.brx = 0.08
			o.hrz = -0.6 * o.brz
			o.hrx = 0.07 * cos(TAU * (2 * u - 0.16))
			o.legMode = 1
		end
	elseif mood == "cheer" or mood == "hop" then
		local cheer = mood == "cheer"
		local period = (if cheer then 0.66 else 0.88) / tempo
		local u = frac(t / period + seed * 0.21)
		if fly then
			o.bty = 0.25 * abs(sin(PI * u)) + 0.04 * sin(t * 18)
			o.bsq = 1 + 0.06 * sin(TAU * u)
			o.wingAmp, o.wingF = 0.75, 18 * tempo
			o.legMode = 6
			o.leg = 0.3
		else
			jump(o, u, if cheer then 1.45 else 1.0, if cheer then 1.05 else 0.9)
		end
		if cheer then
			o.armMode = 2
			o.arm = -2.5 + 0.18 * sin(t * 11)
			o.armZ = 0.22 * sin(t * 10)
			o.jaw = 0.3 + 0.12 * sin(t * 10)
			o.open = true
			o.hrx -= 0.2
			o.ear -= 0.15
			o.tailAmp, o.tailF = 0.5, 16
			o.wingAmp, o.wingF = if fly then o.wingAmp else 0.6, 18
			o.finAmp, o.finF = 0.45, 14
			o.small, o.pincer = 2, 0.4 + 0.3 * abs(sin(t * 12))
		else
			o.armMode = 4
			o.arm = -1 + 0.6 * track(Motion.JUMP.leg, u)
			o.tailAmp, o.tailF = 0.4, 12
			o.wingAmp, o.wingF = 0.4, 14
			o.small = 1.5
		end
	elseif mood == "attack" then
		local L = Motion.LUNGE
		o.brx = track(L.rx, k)
		o.bsq = track(L.sq, k)
		o.btz = track(L.tz, k)
		o.bty = 0.06 * max(0, track(L.sq, k) - 1) * 6
		o.hrx = track(L.head, k)
		o.htz = 0.6 * max(0, track(L.tz, k))
		o.jaw = if k > 0.28 and k < 0.75 then 0.5 * sin((k - 0.28) / 0.47 * PI) else 0.08
		o.open = k > 0.3 and k < 0.72
		o.armMode = 5
		o.arm = track(L.arm, k)
		o.legMode = 2
		o.leg = -0.3 * track(L.rx, k)
		o.tailAmp, o.tailF, o.tailRx = 0.35, 14, 0.4 * max(0, track(L.rx, k))
		o.wingAmp, o.wingF = 0.6, 20
		o.finAmp, o.finF = 0.4, 14
		o.small, o.pincer = 2, 0.9 * max(0, sin(min(1, k / 0.5) * PI))
	elseif mood == "hurt" then
		-- the hit: squashed hard at once, wobbling back (an exaggerated squash that settles), flung back, shaking
		local a = max(0, age)
		local wob = exp(-a * 6) * cos(a * 22)
		o.bsq = 1 - 0.22 * wob
		o.brx = -0.3 * exp(-a * 5) - 0.12
		o.brz = 0.1 * sin(a * 40) * exp(-a * 4)
		o.hrx = -0.44 * exp(-a * 4) - 0.16
		o.hry = 0.25
		o.ear, o.droop = 0.7, 0.5
		o.armMode = 2
		o.arm = -1 + 0.2 * sin(a * 30)
		o.armZ = 0.4
		o.jaw, o.open, o.shut = 0.5, true, true
		o.tailRx, o.tailAmp, o.tailF = -0.2, 0.08, 20
		o.wingRest, o.wingAmp = 0.6, 0.05
		o.pincer = 0.5
	elseif mood == "ko" then
		o.bsq, o.bty, o.brx = 0.9, -0.06, 0.1
		o.hrx, o.hrz = 0.5, 0.26
		o.ear, o.droop = 0.7, 1
		o.armMode, o.arm = 2, -0.35
		o.legMode, o.leg = 5, 0.35
		o.jaw, o.shut = 0.17, true
		o.tailAmp, o.tailRx = 0, -0.17
		o.wingRest, o.wingAmp = -0.35, 0
		o.finAmp = 0
	elseif mood == "peck" then
		local u = frac((t + seed) / (1.7 / tempo))
		local pitch = PITCH[gait] or 1
		local h = track(Motion.PECK, u) * (0.55 + 0.45 * pitch)
		local strike = max(0, h)
		o.hrx = h
		o.brx = 0.32 * pitch * track(Motion.PECK, frac(u - 0.04)) -- (the body follows the head: overlapping action)
		o.bsq = 1 - 0.07 * strike / 0.72
		o.bty = -0.03 * strike
		o.jaw = if h > 0.3 then 0.28 else 0
		o.open = o.jaw > 0.12
		o.tailRx, o.tailAmp, o.tailF = -0.25 * strike, 0.12, 3
		o.armMode, o.arm = 4, -0.3 * strike
		breathe(o, t, 0.6)
	elseif mood == "push" then
		local u = frac(tt * 4 / TAU)
		o.u = u
		o.brx, o.hrx = 0.22, 0.16
		o.bsq = 0.95 + 0.02 * sin(t * 4)
		o.bty = -0.03 + 0.03 * abs(sin(t * 4))
		o.legMode, o.leg = 4, 0
		o.armMode, o.arm = 4, -1.2 + 0.05 * sin(t * 22) -- (straining: a fine shake)
		o.tailAmp, o.tailF = 0.15, 4
		o.wingAmp, o.wingF = 0.2, 6
	elseif mood == "dip" then
		local u = frac((t + seed) / (3 / tempo))
		local d = track(Motion.DIP, u)
		local pitch = PITCH[gait] or 1
		o.brx = (0.08 + 0.22 * d) * pitch
		o.hrx = (0.18 + 0.42 * d) * (0.55 + 0.45 * pitch)
		o.bsq = 1 - 0.03 * d
		local snap = u > 0.58 and u < 0.7
		o.jaw = if snap then 0.42 else 0
		o.open = snap
		o.tailAmp, o.tailF, o.tailRx = 0.12, 2, 0.15 * d
		o.armMode, o.arm = 4, -0.4 * d
		breathe(o, t, 0.5)
	elseif mood == "wave" then
		local up = max(0, sin(t * 6))
		o.bty = 0.05 * up
		o.bsq = 1 + 0.035 * up - 0.02 * max(0, -sin(t * 6))
		o.bry = 0.15 * sin(t * 1.5)
		o.hrz = 0.12 * sin(t * 3) -- (a tilt of the head: appeal)
		o.jaw = 0.2 * max(0, sin(t * 9))
		o.open = o.jaw > 0.1
		o.armMode, o.arm, o.armZ = 3, -2.5, 0.42 * sin(t * 9)
		o.tailAmp, o.tailF = 0.4, 12
		o.wingAmp, o.wingF = 0.4, 9
		o.small = 1.5
	elseif mood == "nap" then
		o.bty, o.bsq, o.brx = -0.12, 0.94, 0.05
		breathe(o, t * 0.75, 1.4)
		o.hrx, o.hry = 0.42, 0.1
		o.ear, o.droop = 0.45, 0.4
		o.tailAmp, o.tailF, o.tailCurl = 0.04, 1.2, 0.6
		o.legMode, o.leg = 5, 0.5
		o.armMode, o.arm = 2, -0.3
		o.wingRest, o.wingAmp = -0.3, 0.02
		o.shut = true
		o.small = 0.5
	else
		-- idle: breathing, the weight shifting, a look about now and then, a yawn, twitching ears, a lazy tail
		breathe(o, t, 1)
		o.brz = 0.035 * track(Motion.WEIGHT, frac((t + seed * 3) / 8))
		o.hrz = -0.5 * o.brz
		local win = floor((t + seed * 2) / 6)
		local side = if win % 2 == 0 then 1 else -1
		local look = track(Motion.LOOK, frac((t + seed * 2) / 6))
		o.hry = 0.3 * look * side
		o.hrz += 0.07 * look * side
		o.hrx = 0.04 * sin(t * 1.3 + 0.5) + (if look < 0 then 0.5 * look else 0)
		local yu = ((t + seed * 5) % 11) / 1.8
		if yu < 1 then
			o.jaw = track(Motion.YAWN.jaw, yu)
			o.hrx += track(Motion.YAWN.head, yu)
			o.bsq *= 1 + track(Motion.YAWN.sq, yu)
			o.open = o.jaw > 0.12
			o.shut = o.shut or (yu > 0.4 and yu < 0.8)
		end
		o.armMode, o.arm = 0, 0.08 * sin(t * 2)
		if fly then
			o.bty += 0.15 * sin(TAU * t * 0.4) + 0.04 * sin(t * 11 - 0.9)
			o.wingAmp, o.wingF = 0.5, 11
			o.legMode, o.leg = 6, 0.2
		end
	end
	return o
end

------------------------------------------------------------------ a bone's pose
-- A bone's pose under a program: its kind ("body", "head", "neck", "jaw", "ear", "arm", "leg", "tail", "wing",
-- "fin", "stalk", "pincer", "tendril", "antenna"), its side (-1 left, 1 right, 0 middle) and phase (a leg's place in the
-- stride 0..1, a tail or wing segment's number down the chain).
function Motion.bone(o: Prog, kind: string, side: number, ph: number): (number, number, number, number, number, number, number)
	local t = o.t
	if kind == "body" then
		return o.brx, o.bry, o.brz, o.btx, o.bty, o.btz, o.bsq
	elseif kind == "head" then
		return o.hrx, o.hry, o.hrz, 0, 0, o.htz, o.hsq
	elseif kind == "neck" then
		return o.hrx * 0.5, o.hry * 0.5, o.hrz * 0.5, 0, 0, o.htz * 0.5, 1
	elseif kind == "jaw" then
		return o.jaw, 0, 0, 0, 0, 0, 1
	elseif kind == "ear" then
		-- a twitch now and then on each ear by itself (left and right never together: appeal), flicked out fast
		local tw = (t + side * 0.9 + 0.3) % (2.6 + side * 0.35)
		local a = (if tw < 0.3 then 0.32 * o.twitch * track(Motion.TWITCH, tw / 0.3) else 0)
		-- (a droop folds the ear back as well as out; a perk, o.ear under 0, stands it up and forward)
		local e = o.ear
		local back = if e > 0 then -0.75 * e else -0.4 * e
		return back, 0, -side * (a + (if e > 0 then 0.45 * e else e)), 0, 0, 0, o.earSq
	elseif kind == "arm" then
		local m = o.armMode
		local rx, rz = 0, 0
		if m == 0 then
			rx = o.arm + 0.04 * sin(t * 2 + side)
		elseif m == 1 then
			-- with the stride, against the legs, a beat behind them
			rx = -0.42 * sin(TAU * (o.u + 0.5 - 0.06) + (if side > 0 then PI else 0))
		elseif m == 2 then
			rx = o.arm
			rz = -side * o.armZ
		elseif m == 3 then
			if side > 0 then
				rx, rz = o.arm, -side * (0.25 + o.armZ)
			else
				rx = -0.2
			end
		elseif m == 4 then
			rx = o.arm
		elseif m == 5 then
			rx = o.arm * (if side > 0 then 1 else 0.6) -- (the far arm less: no twins)
		end
		return rx, 0, rz, 0, 0, 0, 1
	elseif kind == "leg" then
		local m = o.legMode
		if m == 1 or m == 4 then
			-- swinging, the foot lifting on the way forward
			local amp = if m == 4 then 0.36 else 0.5
			local w = TAU * (o.u + ph)
			return amp * sin(w), 0, 0, 0, 0.08 * max(0, cos(w)), 0, 1
		elseif m == 2 then
			return o.leg * (if side < 0 then 1 else 0.92), 0, 0, 0, 0, 0, 1
		elseif m == 3 then
			local s = sin(TAU * (o.u * 1.5 + ph))
			return 0, 0, side * 0.26 * s, 0, 0.06 * max(0, s), 0, 1
		elseif m == 5 then
			return o.leg, 0, 0, 0, 0, 0, 1
		elseif m == 6 then
			return o.leg + 0.12 * sin(t * 3 + side), 0, 0, 0, 0, 0, 1
		end
		return 0, 0, 0, 0, 0, 0, 1
	elseif kind == "tail" then
		-- each segment a little later than the one before, the later ones less (a wave down it)
		local seg = if ph >= 2 then 0.55 else 1
		local ry = o.tailAmp * seg * sin(t * o.tailF - ph * 0.8 + side) + o.tailCurl * seg
		return o.tailRx * seg, ry, 0, 0, 0, 0, 1
	elseif kind == "wing" then
		-- a flap: the downstroke quicker than the upstroke, each outer segment a little later
		local w = t * o.wingF - ph * 0.6
		local f = sin(w)
		f = if f < 0 then -(-f) ^ 0.7 else f ^ 1.3
		return 0, 0, side * (o.wingRest + o.wingAmp * f), 0, 0, 0, 1
	elseif kind == "fin" then
		local a = o.finAmp * sin(t * o.finF + side)
		if side ~= 0 then
			return 0, 0, side * a, 0, 0, 0, 1
		end
		return 0, a, 0, 0, 0, 0, 1
	elseif kind == "stalk" then
		local s = o.small
		return -0.5 * o.droop, 0, side * 0.16 * s * sin(t * 2.3 * s + side), 0, 0, 0, 1
	elseif kind == "pincer" then
		local open = if o.pincer > 0 then o.pincer else 0.24 * max(0, sin(t * 2.4 + side))
		return -open, 0, 0, 0, 0, 0, 1
	elseif kind == "tendril" then
		local s = o.small
		local amp = 0.2 * s * (if ph % 1 > 0 then 0.6 else 1)
		return amp * sin(t * 3 * s + ph) + 0.5 * o.droop, 0, 0.1 * sin(t * 2 + ph * 1.7), 0, 0, 0, 1
	elseif kind == "antenna" then
		local s = o.small
		return 0.17 * s * sin(t * 4 * s + side) + 0.45 * o.droop, 0, 0, 0, 0, 0, 1
	end
	return 0, 0, 0, 0, 0, 0, 1
end

return Motion
