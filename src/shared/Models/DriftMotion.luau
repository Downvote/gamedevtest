--!strict
-- The driftlings' motion (GAME_DESIGN 6; docs/ARCHITECTURE.md 6): what each bone of a driftling's skeleton
-- (Models/DriftRig) does at a moment, in each mood. Pure maths, no instances (tests/specs/DriftMotion.spec.luau).
--
-- The request (2026-11-14): "right now, the models simply move by rotating or moving parts of the mesh around. please
-- use bones and rigging to make more realistic and detailed movement. follow and use as many animation principles
-- when animating as well."
--
-- The request (2026-11-16): "Pose and animate them in ways that make them look natural and lively and bring out what
-- they are more". So each body plan has its own manner (`STYLE`, by the rig's `style`: the plan's name unless the
-- species' form names another): how it holds itself at rest (its carriage: a cat's tail up with a curl at the tip, a
-- rabbit's ears up, an owl upright, a bird's body tipped forward, a dog's tail high and wagging a little), the idle
-- acts it plays one at a time every few seconds (`ACTS`: a dog wags, sniffs, tilts its head, shakes off and bows to
-- play; a cat grooms a raised paw, stretches and blinks slowly; an elephant swings its trunk and flaps its ears; an
-- owl turns its head far round; a frog pulses its throat), and how it walks and cheers (a bird's head bobbing in
-- step, a lizard bending side to side, a penguin's waddle; a bird flapping as it jumps, a frog's big leap, a crab's
-- claws up and snapping, an elephant's trunk raised). Each act is keyed and eased, starts and ends at the rest pose,
-- and is picked by the driftling's seed, so no two move together.
--
-- A mood is a "program": once a frame it works out a handful of shared values from keyed curves (a key is a time, a
-- value and how the curve eases into it), and each bone reads its pose from them: three turns (rx, ry, rz, radians,
-- about its pivot), a shift (tx, ty, tz, studs) and a stretch along the bone (sq: 1 as built, over 1 longer and
-- thinner, under 1 squashed and wider, its volume kept). Turns: +rx tips a part forward (a head nods down, a leg's
-- foot swings back, a tail rises), +ry turns it toward its right (+X), +rz rolls its top toward its left (-X).
-- Where the twelve principles are:
--   squash and stretch: the body squashes before a jump and on landing and stretches as it leaves the ground and as
--     it falls (`JUMP`), settles a little at each step's contact and rises as it passes over the planted foot (`WALK`),
--     breathes in and out, squashes on a hit and wobbles back, stretches into a peck or a lunge; ears stretch as they
--     perk up; a jelly's bell squashes and stretches as it swims; a snail's stalks stretch out.
--   anticipation: a crouch before every jump, a lean back before a lunge or a head butt, the head dipping the other
--     way before it turns to look about, rising before a peck, a breath in before a yawn or a howl, a squash before
--     a shake, the fox's wiggle before it pounces.
--   staging: one clear action at a time (one idle act at a time, never two); the head turns toward what it looks at.
--   straight ahead and pose to pose: the keyed poses here (pose to pose) and the rig's springs (straight ahead:
--     Models/DriftRig works out the ears, tails, antennae, tendrils, stalks, fins and wing tips frame by frame).
--   follow through and overlapping action: the head's nod comes a beat after the body's step, the arms swing a beat
--     after the legs, the tail's segments wave each a little later; a mushroom's cap lags its bounce; the springs
--     carry on after the body stops.
--   slow in and slow out: every key eases (`EASE`), every act fades in and out (`env`), cycles are sines.
--   arcs: every bone turns about its pivot, a jump rises and falls on a curve, a lunge goes forward and down.
--   secondary action: blinks (a blink as the head turns), ear twitches, breathing, a tail sway while it pecks or naps.
--   timing: a bigger driftling moves slower (`tempo`), a jump spends longer in the air than on the ground, a peck
--     strikes fast and comes back slowly; a bird snaps its head round and holds, an owl turns slowly; a rabbit breathes
--     fast and an elephant slowly.
--   exaggeration: a cheer jumps higher and squashes harder than a hop; a hit squashes hard.
--   solid drawing: the weight shifts onto the planted foot, the hips twist with the stride, the head keeps level
--     against the body's roll; feet stay planted while the body leans or rises (`plant`).
--   appeal: no twins (left and right a little out of step, each driftling's own phase and acts from its seed), a head
--     tilt with a look.
--   Motion.program(mood, t, age, k, gait, tempo, seed, out, style) -> Prog   (t seconds, age: seconds in this mood,
--     k an action's progress 0..1, gait "quad" | "biped" | "hop" | "scuttle" | "slither" | "fly", style a STYLE name)
--   Motion.bone(prog, kind, side, phase, dx, dz) -> (rx, ry, rz, tx, ty, tz, sq)   (dx, dz: the bone's pivot from
--     the root's, studs)
--   Motion.STYLE, Motion.style(name), Motion.ACTS, Motion.actAt(style, t, seed, tempo), Motion.act(prog, name, u, t,
--     side, style); Motion.ease(id, x), Motion.track(keys, u), Motion.JUMP and the other key sets (the specs read them)
local Motion = {}

local PI = math.pi
local TAU = 2 * math.pi
local sin, cos, exp, max, min, abs, floor, sqrt = math.sin, math.cos, math.exp, math.max, math.min, math.abs, math.floor, math.sqrt

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

-- 0 before a, eased up to 1 by b, held, eased back down to 0 from c to d (0 <= a <= b <= c <= d <= 1): an act's
-- envelope, so it starts and ends at rest
local function env(u: number, a: number, b: number, c: number, d: number): number
	if u <= a or u >= d then
		return 0
	end
	if u < b then
		local x = (u - a) / (b - a)
		return x * x * (3 - 2 * x)
	end
	if u <= c then
		return 1
	end
	local x = (d - u) / (d - c)
	return x * x * (3 - 2 * x)
end

-- a smooth bump from a to b: 0 at both ends (and still there), 1 in the middle
local function bump(u: number, a: number, b: number): number
	if u <= a or u >= b then
		return 0
	end
	return 0.5 - 0.5 * cos(TAU * (u - a) / (b - a))
end

-- a number in 0..1 from a window's number and a driftling's seed
local function hash(n: number, seed: number): number
	return frac(sin(n * 12.9898 + seed * 78.233) * 43758.5453)
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
	-- (the legs, + forward: folding into the crouch, kicking back to push off, tucked in the air, reaching to land,
	-- bending)
	leg = { { 0, 0 }, { 0.14, 0.55, OUT }, { 0.26, -0.5, IN }, { 0.44, 0.3, OUT }, { 0.7, -0.18, SMOOTH }, { 0.82, 0.42, OUT }, { 1, 0, SMOOTH } },
}
-- A walk (the request of 2026-11-15: "most creatures seem to walk around by bouncing instead of actually walking.
-- could you animate them to walk instead of bouncing?"): no hop. Each foot is planted for `duty` of the stride,
-- sweeping back steadily as the body passes over it, then lifts and swings forward quickly (eased) to plant again,
-- `lift` studs at the top of its swing; the body rises `bob` studs as it passes over a planted leg and settles as the
-- other comes down (a slight squash `sq` there), rolls toward the planted side and twists its hips with the stride.
-- `rate`: strides a second at tempo 1 (quicker than the old bouncy walk's, so the feet keep up with the ground).
Motion.WALK = { duty = 0.6, amp = 0.55, lift = 0.1, bob = 0.035, sq = 0.02, roll = 0.035, twist = 0.05, rate = 1.9 }
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

-- The idle acts' own keys (over each act's time): a look (a turn the other way first, past the mark, a hold, home)
-- and a bird's or a lizard's look (snapped round, held, snapped the other way, held, home); a curious head tilt (a
-- dip the other way, past the mark, a hold, then the other side); an owl's slow turn far round; a quick look and back;
-- an ear flicked back fast (the first, then the second); a rabbit's thumping foot; a heavy foot stamped; wings folded
-- in, then spread wide.
local LOOK_SMOOTH = { { 0, 0 }, { 0.08, -0.1, OUT }, { 0.27, 1.08, OUT }, { 0.36, 1, SMOOTH }, { 0.7, 1, SMOOTH }, { 0.92, 0, SMOOTH }, { 1, 0 } }
local LOOK_SNAP = { { 0, 0 }, { 0.05, 1, OUT }, { 0.34, 1, SMOOTH }, { 0.4, -0.75, OUT }, { 0.7, -0.75, SMOOTH }, { 0.76, 0, OUT }, { 1, 0 } }
local TILT = { { 0, 0 }, { 0.08, -0.15, OUT }, { 0.24, 1, BACK }, { 0.46, 1, SMOOTH }, { 0.6, -0.8, SMOOTH }, { 0.8, -0.8, SMOOTH }, { 1, 0, SMOOTH } }
local TURN = { { 0, 0 }, { 0.06, -0.06, OUT }, { 0.3, 1, SMOOTH }, { 0.64, 1, SMOOTH }, { 0.86, 0, SMOOTH }, { 1, 0 } }
local HFLICK = { { 0, 0 }, { 0.06, 1, OUT }, { 0.5, 1, SMOOTH }, { 0.56, 0, OUT }, { 1, 0 } }
local FLICK1 = { { 0, 0 }, { 0.07, 1, OUT }, { 0.4, 0, SMOOTH }, { 1, 0 } }
local FLICK2 = { { 0, 0 }, { 0.45, 0 }, { 0.52, 1, OUT }, { 0.85, 0, SMOOTH }, { 1, 0 } }
local THUMP = { { 0, 0 }, { 0.3, 1, OUT }, { 0.5, 1, SMOOTH }, { 0.56, 0, IN }, { 0.72, 0 }, { 0.76, 0.6, OUT }, { 0.82, 0, IN }, { 1, 0 } }
local STOMP = { { 0, 0 }, { 0.32, 1, OUT }, { 0.48, 1, SMOOTH }, { 0.55, 0, IN }, { 1, 0 } }
local FOLD = { { 0, 0 }, { 0.22, -1, SMOOTH }, { 0.4, -1, SMOOTH }, { 0.6, 1, OUT }, { 0.8, 1, SMOOTH }, { 1, 0, SMOOTH } }
local WAG_F = 15 -- radians a second: a wag's beat (a fixed beat: only its strength changes, so it never skips)
local TEND_F = 4.5 -- a tendril's or a trunk's wave in an act
local ANT_F = 9 -- an antenna's quick wave

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
	-- ears: a turn out (+ droops, - perks) and a twitch's strength, each side's own droop (earL, earR) and swivel (earYL,
	-- earYR: + the opening turns out and back)
	ear: number,
	earSq: number,
	twitch: number,
	earL: number,
	earR: number,
	earYL: number,
	earYR: number,
	-- arms
	armMode: number, -- 0 swaying, 1 swinging with the stride, 2 raised, 3 one waving, 4 forward, 5 striking
	arm: number, -- the arms' turn (radians, about X: - raises them forward and up)
	armZ: number,
	armL: number, -- each arm's own turn (- forward and up) and turn out from the body (armLz, armRz), in any mode
	armR: number,
	armLz: number,
	armRz: number,
	-- legs
	legMode: number, -- 0 standing, 1 walking, 2 jumping, 3 scuttling, 4 pacing, 5 folded, 6 dangling, 7 walking with the
	-- legs taking turns left and right (a hopper's legs are built in step: Motion.WALK)
	leg: number,
	u: number, -- the stride's or jump's phase (0..1)
	legF: number, -- standing: the forelegs' turn (a four-legged one's; any other's legs all count as fore), + forward
	legH: number, -- the hind legs'
	liftLeg: number, -- the one leg lifted: 1 fore left, 2 fore right, 3 hind left, 4 hind right (two legs: 1, 2)
	legLift: number, -- how far it swings forward (radians, - back)
	legUp: number, -- and up (studs)
	plant: number, -- 0..1: the feet kept on the ground while the body leans, rolls back or rises (standing)
	free: number, -- 0..1: a four-legged one's forelegs let off the ground (it sits up)
	shuffle: number, -- 0..1: the standing legs stepping on the spot as they scuttle (by u)
	-- tails
	tailAmp: number,
	tailF: number,
	tailRx: number,
	tailCurl: number,
	tailRy: number, -- the tail turned to one side (+ to its left)
	tailTip: number, -- its tip curled (+ up)
	wag: number, -- a quick wag's strength (at WAG_F)
	-- wings, fins
	wingAmp: number,
	wingF: number,
	wingRest: number,
	wingL: number, -- each wing raised (+) or folded in (-)
	wingR: number,
	finAmp: number,
	finF: number,
	finY: number, -- side fins swept forward (+)
	finZ: number, -- and raised (+)
	-- the small parts
	small: number, -- stalks, antennae, tendrils, pincers: how lively (1 calm .. 2 excited); keep it the same for a mood
	pincer: number,
	droop: number, -- small parts droop (hurt, out cold)
	stalkSq: number, -- eye stalks stretched (over 1) or drawn in
	stalkX: number, -- tipped forward (+)
	stalkZ: number, -- spread (+) or together
	stalkTurn: number, -- both turned to one side
	tendrilAmp: number, -- tendrils' (and a trunk's) extra wave at TEND_F
	tendrilRx: number, -- their first segments tipped (- forward and up: a trunk raised)
	tendrilTip: number, -- their later segments
	tendrilRz: number, -- swung to one side
	flare: number, -- spread out from the middle (+) or drawn in (a jelly's or an octopus's pulse)
	antAmp: number, -- antennae's extra quick wave
	antRx: number, -- tipped forward (+) or raised
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
		earL = 0,
		earR = 0,
		earYL = 0,
		earYR = 0,
		armMode = 0,
		arm = 0,
		armZ = 0,
		armL = 0,
		armR = 0,
		armLz = 0,
		armRz = 0,
		legMode = 0,
		leg = 0,
		u = 0,
		legF = 0,
		legH = 0,
		liftLeg = 0,
		legLift = 0,
		legUp = 0,
		plant = 0,
		free = 0,
		shuffle = 0,
		tailAmp = 0.17,
		tailF = 2.2,
		tailRx = 0,
		tailCurl = 0,
		tailRy = 0,
		tailTip = 0,
		wag = 0,
		wingAmp = 0.1,
		wingF = 3,
		wingRest = 0,
		wingL = 0,
		wingR = 0,
		finAmp = 0.1,
		finF = 2.5,
		finY = 0,
		finZ = 0,
		small = 1,
		pincer = 0,
		droop = 0,
		stalkSq = 1,
		stalkX = 0,
		stalkZ = 0,
		stalkTurn = 0,
		tendrilAmp = 0,
		tendrilRx = 0,
		tendrilTip = 0,
		tendrilRz = 0,
		flare = 0,
		antAmp = 0,
		antRx = 0,
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
	o.ear, o.earSq, o.twitch, o.earL, o.earR, o.earYL, o.earYR = 0, 1, 1, 0, 0, 0, 0
	o.armMode, o.arm, o.armZ, o.armL, o.armR, o.armLz, o.armRz = 0, 0, 0, 0, 0, 0, 0
	o.legMode, o.leg, o.u = 0, 0, 0
	o.legF, o.legH, o.liftLeg, o.legLift, o.legUp, o.plant, o.free, o.shuffle = 0, 0, 0, 0, 0, 0, 0, 0
	o.tailAmp, o.tailF, o.tailRx, o.tailCurl, o.tailRy, o.tailTip, o.wag = 0.17, 2.2, 0, 0, 0, 0, 0
	o.wingAmp, o.wingF, o.wingRest, o.wingL, o.wingR = 0.1, 3, 0, 0, 0
	o.finAmp, o.finF, o.finY, o.finZ = 0.1, 2.5, 0, 0
	o.small, o.pincer, o.droop = 1, 0, 0
	o.stalkSq, o.stalkX, o.stalkZ, o.stalkTurn = 1, 0, 0, 0
	o.tendrilAmp, o.tendrilRx, o.tendrilTip, o.tendrilRz, o.flare = 0, 0, 0, 0, 0
	o.antAmp, o.antRx = 0, 0
	o.shut, o.open = false, false
end

-- How far a body plan's body pitches: a long body (four legs, a serpent) tips its head a long way for a small turn.
local PITCH: { [string]: number } = { quad = 0.45, slither = 0.3, scuttle = 0.6, fly = 0.6 }

------------------------------------------------------------------ the styles
-- Each body plan's manner. Its carriage (the rest pose, every frame it stands about): `lean` the body's pitch (+
-- forward), `head` the head's (+ down), `ear` (- perked, + relaxed) and `twitch` (an ear twitch's strength), `tail` (+
-- raised), `tip` (its tip curled up), `sway` and `swayF` (the tail's lazy sway and its speed), `wag` (a dog's wag at
-- rest), `breath` and `breathT` (how deep, seconds a breath), `weight` (the weight shifting from foot to foot), `arm`
-- and `armOut` (arms forward and out), `wing`, `wingAmp`, `wingF` (wings raised, their beat and its speed: the same
-- in every act, so a beat never skips), `hover` and `hoverF` (a flyer's bob, studs and beats a second), `finAmp`,
-- `finF`, `small` (stalks, antennae, tendrils: how lively), `fluke` (a whale's tail beating up and down). Its looks:
-- `look` (how far it turns its head), `tilt` (how far it tilts it), `snap` (0 smooth turns .. 1 snapped round and
-- held), `lookBody` (how much the body turns with the head), `reach` (how far the head goes down to sniff, graze or
-- peck). Its idle `acts` (ACTS), one every `every` seconds or so (a few windows go by with none). Its walk: `bob` (a
-- bird's head bobbing in step, studs), `nod` (a hoofed one's head nodding with the steps), `walkWag`, `walkTail` (the
-- tail's carriage walking), `roll` (how far it rolls from foot to foot: a waddle), `bend` (a lizard's side to side
-- bend; for a slither, its sway), `heavy` (0..1: a bigger bob and a slower sway of the head), `hump` (a seal's
-- humping crawl), `pulse` (a jelly's or an octopus's swimming pulse), `flyWing` and `flyWingF` (a flyer's beat as it
-- goes). Its cheer: "jump", "flap" (wings beating as it jumps), "leap" (a frog's big jump), "splash" (a swimmer's leap
-- and flick), "claws" (claws up and snapping), "wave" (tendrils waving), "wag" (a frantic wag), "trumpet" (a trunk up),
-- "clap" (flippers clapping), "bounce" (a cap bouncing after), "flutter", "pound" (fists up in turn), "binky" (a
-- rabbit's twist in the air).
export type Style = {
	acts: { string },
	every: number,
	lean: number,
	head: number,
	look: number,
	tilt: number,
	snap: number,
	lookBody: number,
	reach: number,
	ear: number,
	twitch: number,
	tail: number,
	tip: number,
	sway: number,
	swayF: number,
	wag: number,
	breath: number,
	breathT: number,
	weight: number,
	arm: number,
	armOut: number,
	wing: number,
	wingAmp: number,
	wingF: number,
	hover: number,
	hoverF: number,
	finAmp: number,
	finF: number,
	small: number,
	fluke: number,
	bob: number,
	nod: number,
	walkWag: number,
	walkTail: number,
	roll: number,
	bend: number,
	heavy: number,
	hump: number,
	pulse: number,
	flyWing: number,
	flyWingF: number,
	cheer: string,
}

-- (the old idle's manner: a look about now and then and a yawn; an unknown style gets it)
local DEF: Style = {
	acts = { "look", "look", "yawn" },
	every = 6,
	lean = 0,
	head = 0,
	look = 0.3,
	tilt = 0.14,
	snap = 0,
	lookBody = 0.1,
	reach = 1,
	ear = 0,
	twitch = 1,
	tail = 0,
	tip = 0,
	sway = 0.17,
	swayF = 2.2,
	wag = 0,
	breath = 1,
	breathT = 3.1,
	weight = 1,
	arm = 0,
	armOut = 0,
	wing = 0,
	wingAmp = 0.1,
	wingF = 3,
	hover = 0.15,
	hoverF = 0.4,
	finAmp = 0.1,
	finF = 2.5,
	small = 1,
	fluke = 0,
	bob = 0,
	nod = 0,
	walkWag = 0,
	walkTail = 0,
	roll = 1,
	bend = 0,
	heavy = 0,
	hump = 0,
	pulse = 0,
	flyWing = 0.7,
	flyWingF = 12,
	cheer = "jump",
}

local function style(o: { [string]: any }): Style
	local s: { [string]: any } = table.clone(DEF :: any)
	for k, v in o do
		s[k] = v
	end
	if o.walkTail == nil then
		s.walkTail = s.tail
	end
	return (s :: any) :: Style
end

local STYLE: { [string]: Style } = {
	-- four-legged
	pup = style({ acts = { "wag", "sniff", "tilt", "shake", "bow", "scratch", "look", "howl", "pounce", "yawn" }, every = 4.5, ear = -0.08, twitch = 1.2, tail = 0.28, tip = 0.1, sway = 0.1, swayF = 5, wag = 0.07, breath = 1.1, breathT = 1.7, head = -0.04, look = 0.36, tilt = 0.2, walkWag = 0.2, walkTail = 0.32, cheer = "wag" }),
	cat = style({ acts = { "flick", "groom", "stretch", "blink", "knead", "tilt", "look", "yawn" }, every = 5, ear = -0.05, tail = 0.5, tip = 0.45, sway = 0.07, swayF = 1.3, breath = 0.9, breathT = 3.4, look = 0.32, tilt = 0.17, walkTail = 0.6, roll = 0.7, cheer = "jump" }),
	bear = style({ acts = { "sniffair", "sway", "scratch", "sniff", "situp", "yawn", "look" }, every = 6, head = 0.08, sway = 0.05, swayF = 1.5, breath = 1.3, breathT = 3.8, weight = 1.4, look = 0.26, heavy = 0.6, roll = 1.5, nod = 0.04, cheer = "jump" }),
	otter = style({ acts = { "situp", "groomface", "sniff", "tilt", "look", "dig" }, every = 4.5, tail = -0.05, sway = 0.12, swayF = 1.8, breath = 1, breathT = 2.4, look = 0.36, snap = 0.3, tilt = 0.2, bend = 0.3, cheer = "jump" }),
	deer = style({ acts = { "swivel", "graze", "alert", "flick", "earflick", "look", "tilt" }, every = 5, head = -0.05, ear = -0.1, twitch = 1.4, tail = 0.15, sway = 0.1, swayF = 3, breath = 0.9, breathT = 2.6, look = 0.32, reach = 1.1, nod = 0.08, roll = 0.8, cheer = "jump" }),
	ram = style({ acts = { "butt", "ruminate", "graze", "shake", "earflick", "look" }, every = 5.5, head = 0.04, sway = 0.1, swayF = 4, breath = 1.1, breathT = 3, weight = 1.2, look = 0.28, reach = 0.9, nod = 0.06, cheer = "jump" }),
	elephant = style({ acts = { "trunk", "earflap", "stomp", "trunkup", "sway", "look" }, every = 5.5, ear = 0.1, twitch = 0.6, tail = -0.1, sway = 0.12, swayF = 1.6, breath = 1.4, breathT = 4.2, weight = 1.6, small = 0.6, look = 0.22, heavy = 1, roll = 1.6, nod = 0.06, cheer = "trumpet" }),
	griffin = style({ acts = { "preen", "ruffle", "flap", "stretchwing", "look", "tilt" }, every = 5, head = -0.08, look = 0.42, snap = 0.6, tilt = 0.22, tail = 0.1, tip = 0.3, sway = 0.1, swayF = 2, wingAmp = 0, wingF = 15, bob = 0.02, cheer = "flap" }),
	drake = style({ acts = { "stretchwing", "swish", "snort", "shake", "look", "yawn" }, every = 5.5, head = -0.04, tip = 0.2, sway = 0.12, swayF = 1.2, wing = 0.04, wingAmp = 0.02, wingF = 10, breath = 1.3, breathT = 3.4, look = 0.3, bend = 0.15, roll = 1.1, cheer = "flap" }),
	mole = style({ acts = { "sniff", "dig", "groomface", "sniffair", "look", "tilt" }, every = 4.5, head = 0.05, lean = 0.04, sway = 0.15, swayF = 6, breath = 1.1, breathT = 1.8, look = 0.3, snap = 0.4, roll = 1.2, bend = 0.1, cheer = "jump" }),
	hedgehog = style({ acts = { "sniff", "curl", "twitch", "shake", "look", "tilt" }, every = 4.5, head = 0.06, lean = 0.03, sway = 0.04, breath = 1.2, breathT = 1.6, look = 0.3, snap = 0.3, roll = 1.3, cheer = "jump" }),
	armadillo = style({ acts = { "sniff", "curl", "dig", "look", "tilt" }, every = 5, head = 0.06, ear = -0.05, tail = -0.05, sway = 0.08, swayF = 2, breath = 1.1, breathT = 2, look = 0.28, roll = 1.2, cheer = "jump" }),
	turtle = style({ acts = { "tuck", "stretchneck", "blink", "look", "yawn" }, every = 6.5, head = 0.04, tail = -0.1, sway = 0.05, swayF = 1.2, breath = 0.6, breathT = 4.5, weight = 0.8, look = 0.26, heavy = 0.8, roll = 1.4, cheer = "jump" }),
	lizard = style({ acts = { "pushup", "headflick", "tongue", "bask", "swish", "look" }, every = 4, lean = -0.04, head = -0.06, look = 0.4, snap = 1, tilt = 0.1, tail = -0.08, tip = 0.1, sway = 0.06, swayF = 1.4, breath = 0.8, breathT = 2.2, weight = 0.6, bend = 0.6, roll = 0.6, cheer = "jump" }),
	-- two-legged
	monkey = style({ acts = { "scratch", "chest", "swing", "groomface", "look", "tilt", "yawn" }, every = 4.5, lean = 0.08, head = -0.06, arm = 0.1, armOut = 0.12, tail = 0.3, tip = 0.4, look = 0.42, snap = 0.3, tilt = 0.2, breath = 1.1, breathT = 2.4, roll = 1.3, cheer = "pound" }),
	yeti = style({ acts = { "chest", "scratch", "sway", "shoulders", "look", "yawn" }, every = 6, lean = 0.05, arm = 0.05, armOut = 0.2, breath = 1.3, breathT = 3.6, weight = 1.5, look = 0.3, heavy = 0.7, roll = 1.6, cheer = "pound" }),
	golem = style({ acts = { "shoulders", "stomp", "sway", "look", "tilt" }, every = 6.5, lean = 0.04, head = 0.05, arm = 0.05, armOut = 0.12, twitch = 0, breath = 0.5, breathT = 4.5, weight = 1.2, look = 0.26, heavy = 1, roll = 1.8, nod = 0.05, cheer = "pound" }),
	shroom = style({ acts = { "bounce", "shake", "sway", "tilt", "look", "yawn" }, every = 4.5, armOut = 0.1, breath = 1, breathT = 2.8, look = 0.3, tilt = 0.2, heavy = 0.3, cheer = "bounce" }),
	bird = style({ acts = { "peck", "bob", "preen", "ruffle", "flap", "look", "tilt" }, every = 4.4, lean = 0.12, head = -0.12, look = 0.45, snap = 1, tilt = 0.22, tail = 0.1, sway = 0.05, swayF = 3, breath = 1.1, breathT = 0.9, wingAmp = 0, wingF = 16, bob = 0.05, roll = 0.8, cheer = "flap" }),
	owl = style({ acts = { "turn", "tilt", "peer", "blink", "ruffle", "look" }, every = 4.5, lean = -0.04, head = 0.02, ear = -0.05, look = 0.5, snap = 0.3, tilt = 0.4, sway = 0.03, breath = 0.9, breathT = 2.5, wingAmp = 0, wingF = 14, bob = 0.02, roll = 1.4, cheer = "flap" }),
	penguin = style({ acts = { "waddle", "flap", "preen", "shake", "look", "tilt" }, every = 4.5, lean = -0.06, head = 0.02, wing = 0.12, wingAmp = 0, wingF = 14, sway = 0.06, swayF = 4, breath = 1, breathT = 2, look = 0.35, snap = 0.5, tilt = 0.22, roll = 2.5, cheer = "flap" }),
	duck = style({ acts = { "waggle", "preen", "flap", "peck", "bob", "look" }, every = 4.4, lean = 0.04, head = -0.04, tail = 0.15, sway = 0.04, swayF = 3, wingAmp = 0, wingF = 15, breath = 1.1, breathT = 1.2, look = 0.4, snap = 0.8, tilt = 0.18, reach = 0.8, bob = 0.03, roll = 2, cheer = "flap" }),
	-- hoppers
	bun = style({ acts = { "twitch", "earflick", "thump", "situp", "groomface", "hopinplace", "look" }, every = 4.2, ear = -0.18, twitch = 1.6, sway = 0.06, swayF = 8, breath = 1.2, breathT = 1.2, look = 0.3, snap = 0.5, tilt = 0.18, cheer = "binky" }),
	frog = style({ acts = { "throat", "hopinplace", "tongue", "blink", "look", "tilt" }, every = 4, lean = -0.08, head = 0.02, breath = 0.8, breathT = 0.7, look = 0.25, snap = 0.8, tilt = 0.14, cheer = "leap" }),
	-- many-legged
	crab = style({ acts = { "snap", "raise", "stalks", "sidestep", "look" }, every = 4, arm = -0.1, look = 0.25, lookBody = 0.9, small = 1, breath = 0.6, cheer = "claws" }),
	beetle = style({ acts = { "antennae", "clean", "look", "tilt", "sidestep" }, every = 4.5, small = 1.2, look = 0.3, snap = 0.6, lookBody = 0.3, breath = 0.6, cheer = "jump" }),
	-- creeping
	snail = style({ acts = { "stalks", "retract", "look", "stretchneck" }, every = 6, small = 0.8, breath = 0.7, breathT = 4, look = 0.25, bend = -0.6, cheer = "jump" }),
	wyrm = style({ acts = { "coil", "tongue", "sniffair", "look", "yawn" }, every = 5, head = -0.05, sway = 0.2, swayF = 1.2, finAmp = 0.12, finF = 2, breath = 1.1, breathT = 3.4, look = 0.36, tilt = 0.18, bend = 0.3, cheer = "jump" }),
	seal = style({ acts = { "clap", "roll", "tilt", "look", "yawn" }, every = 4.5, lean = -0.04, head = -0.08, tail = 0.1, sway = 0.08, finAmp = 0.06, finF = 2, breath = 1.1, breathT = 2.4, look = 0.35, tilt = 0.22, hump = 1, cheer = "clap" }),
	-- swimmers and flyers (the "fly" gait)
	fish = style({ acts = { "drift", "dart", "bubble", "finflick", "look" }, every = 4, hover = 0.1, hoverF = 0.35, sway = 0.25, swayF = 4, wingAmp = 0, finAmp = 0.25, finF = 6, look = 0.25, lookBody = 0.6, flyWing = 0, cheer = "splash" }),
	ray = style({ acts = { "drift", "ripple", "look" }, every = 5, hover = 0.12, hoverF = 0.3, sway = 0.15, swayF = 2, wingAmp = 0.22, wingF = 3, look = 0.2, lookBody = 0.8, flyWing = 0.45, flyWingF = 4, cheer = "splash" }),
	seahorse = style({ acts = { "drift", "curltail", "finflick", "look", "tilt" }, every = 4.5, lean = -0.05, head = 0.08, hover = 0.06, hoverF = 0.5, sway = 0.06, swayF = 1.2, wingAmp = 0, finAmp = 0.3, finF = 14, look = 0.3, tilt = 0.2, flyWing = 0, cheer = "flutter" }),
	octo = style({ acts = { "wave", "pulse", "look", "tilt" }, every = 4.5, hover = 0.12, hoverF = 0.35, wingAmp = 0, finAmp = 0.15, finF = 3, small = 1.1, look = 0.3, tilt = 0.2, lookBody = 0.5, pulse = 0.6, flyWing = 0, cheer = "wave" }),
	jelly = style({ acts = { "pulse", "drift", "wave" }, every = 4, hover = 0.1, hoverF = 0.3, wingAmp = 0, small = 0.8, breath = 0.5, look = 0.15, lookBody = 1, pulse = 1, flyWing = 0, cheer = "wave" }),
	sprite = style({ acts = { "flutter", "hello", "look", "tilt", "yawn" }, every = 4, armOut = 0.15, hover = 0.15, hoverF = 0.4, wingAmp = 0.5, wingF = 22, look = 0.35, tilt = 0.22, flyWing = 0.6, flyWingF = 24, cheer = "flutter" }),
	bat = style({ acts = { "fold", "earflick", "stretchwing", "look", "tilt" }, every = 4.5, ear = -0.1, twitch = 1.4, hover = 0.18, hoverF = 0.45, wingAmp = 0.55, wingF = 9, look = 0.35, tilt = 0.25, flyWing = 0.7, flyWingF = 11, cheer = "flutter" }),
	moth = style({ acts = { "antennae", "fold", "flutter", "look", "tilt" }, every = 4.5, hover = 0.14, hoverF = 0.3, wingAmp = 0.35, wingF = 7, small = 0.9, look = 0.3, tilt = 0.2, flyWing = 0.6, flyWingF = 9, cheer = "flutter" }),
}
STYLE.default = DEF

-- Species whose manner is not quite their plan's (their forms name these: Data/Creatures or Models/DriftPlans*).
STYLE.lion = style({ acts = { "flick", "yawn", "shake", "blink", "stretch", "look" }, every = 6, ear = 0, tail = 0.1, tip = 0.35, sway = 0.1, swayF = 1.1, breath = 1.2, breathT = 3.8, look = 0.28, tilt = 0.12, walkTail = 0.2, heavy = 0.3, roll = 1, cheer = "jump" })
STYLE.horse = style({ acts = { "paw", "toss", "swish", "graze", "swivel", "look" }, every = 5, head = -0.04, ear = -0.08, twitch = 1.3, tail = 0.05, sway = 0.15, swayF = 2, breath = 1, breathT = 3, look = 0.3, reach = 1.1, nod = 0.1, cheer = "jump" })
STYLE.goat = style({ acts = { "butt", "ruminate", "graze", "hopinplace", "swivel", "look", "tilt" }, every = 5, ear = -0.04, tail = 0.35, sway = 0.2, swayF = 6, breath = 1, breathT = 2.4, look = 0.34, tilt = 0.18, snap = 0.3, nod = 0.07, cheer = "leap" })
STYLE.chameleon = style({ acts = { "rock", "tongue", "headflick", "look" }, every = 5, lean = -0.03, head = -0.04, look = 0.35, snap = 1, tail = -0.05, tip = 0.3, sway = 0.03, swayF = 0.8, breath = 0.6, breathT = 3, weight = 0.5, bend = 0.2, roll = 0.4, cheer = "jump" })
STYLE.croc = style({ acts = { "gape", "swish", "look", "yawn" }, every = 7, head = -0.02, look = 0.18, tail = -0.1, sway = 0.03, swayF = 0.8, breath = 0.6, breathT = 4, weight = 0.4, bend = 0.7, roll = 0.5, cheer = "jump" })
STYLE.axolotl = style({ acts = { "float", "tilt", "tongue", "look" }, every = 4.5, look = 0.3, tilt = 0.2, tail = 0, sway = 0.2, swayF = 2.5, breath = 1, breathT = 2.6, bend = 0.5, roll = 0.6, cheer = "jump" })
STYLE.seaturtle = style({ acts = { "paddle", "stretchneck", "look", "blink" }, every = 5, head = 0.02, tail = -0.1, sway = 0.05, breath = 0.7, breathT = 4, look = 0.26, heavy = 0.6, roll = 1.3, cheer = "jump" })
STYLE.seaotter = style({ acts = { "groomface", "crack", "tilt", "look", "yawn" }, every = 4.5, arm = -0.5, armOut = -0.12, tail = -0.1, sway = 0.08, breath = 1, breathT = 2.4, look = 0.36, snap = 0.3, tilt = 0.22, cheer = "clap" })
STYLE.whale = style({ acts = { "spout", "roll", "drift", "look" }, every = 6, hover = 0.12, hoverF = 0.25, sway = 0.02, swayF = 1, fluke = 0.12, finAmp = 0.12, finF = 1.5, wingAmp = 0, look = 0.15, lookBody = 1, flyWing = 0, cheer = "splash" })
STYLE.heron = style({ acts = { "oneleg", "strike", "preen", "ruffle", "look" }, every = 6, lean = 0.05, head = -0.04, look = 0.32, snap = 0.6, tilt = 0.14, wingAmp = 0, wingF = 15, reach = 1.1, bob = 0.06, cheer = "flap" })
STYLE.skybird = style({ acts = { "flutter", "look", "tilt", "bob" }, every = 4, lean = 0.08, head = -0.08, look = 0.4, snap = 1, tilt = 0.22, wingAmp = 0.55, wingF = 20, flyWing = 0.7, flyWingF = 16, cheer = "flap" })
STYLE.toad = style({ acts = { "throat", "tongue", "blink", "look" }, every = 6, lean = -0.06, breath = 0.7, breathT = 1, look = 0.2, snap = 0.6, heavy = 0.4, cheer = "jump" })
STYLE.hermit = style({ acts = { "retract", "stalks", "snap", "look" }, every = 5, arm = -0.05, small = 0.9, look = 0.2, lookBody = 0.9, breath = 0.5, cheer = "claws" })
STYLE.bee = style({ acts = { "dance", "antennae", "flutter", "look" }, every = 4, hover = 0.1, hoverF = 0.6, wingAmp = 0.45, wingF = 30, small = 1.3, look = 0.3, flyWing = 0.55, flyWingF = 30, cheer = "flutter" })
STYLE.treant = style({ acts = { "rustle", "sway", "shoulders", "look" }, every = 6, lean = 0.03, arm = 0.05, armOut = 0.18, twitch = 0, breath = 0.4, breathT = 4.5, weight = 1.3, look = 0.22, heavy = 1, roll = 1.5, cheer = "pound" })
Motion.STYLE = STYLE

-- A style by name (the plan's or its form's); an unknown name gets the old manner.
function Motion.style(name: string?): Style
	return STYLE[name or "default"] or DEF
end

------------------------------------------------------------------ the idle acts
-- Each act writes on top of the carriage at u (0..1 through it) and time t, `s` the side it favours (-1 left, 1 right).
-- Every act is 0 at u 0 and u 1, so it starts and ends at rest; `dur` its seconds at tempo 1.
type ActFn = (o: Prog, u: number, t: number, s: number, S: Style) -> ()
export type Act = { dur: number, fn: ActFn }
local ACTS: { [string]: Act } = {}
Motion.ACTS = ACTS
local function act(name: string, dur: number, fn: ActFn)
	ACTS[name] = { dur = dur, fn = fn }
end

-- a front paw raised on side s: a four-legged one's foreleg (forward `a`, up `up`), anything else's arm (up `arm`)
local function paw(o: Prog, s: number, a: number, up: number, arm: number)
	if o.gait == "quad" then
		o.liftLeg = if s < 0 then 1 else 2
		o.legLift += a
		o.legUp += up
	elseif s < 0 then
		o.armL -= arm
	else
		o.armR -= arm
	end
end

-- Looking about: the head turns (a counter-turn first, past the mark, held, home; a bird's or a lizard's snapped round
-- and held), tilting a little, the body following, a blink as the head turns.
act("look", 3, function(o, u, t, s, S)
	local k = track(LOOK_SMOOTH, u) * (1 - S.snap) + track(LOOK_SNAP, u) * S.snap
	o.hry += S.look * k * s
	o.hrz += S.tilt * 0.5 * k * s
	o.hrx -= 0.05 * abs(k)
	o.bry += S.lookBody * S.look * k * s
	if S.snap < 0.5 and u > 0.1 and u < 0.135 then
		o.shut = true
	end
end)

-- A curious tilt of the head, one way and then the other, the ears up.
act("tilt", 2.4, function(o, u, t, s, S)
	local k = track(TILT, u)
	o.hrz += max(0.22, S.tilt * 1.5) * k * s
	o.hrx -= 0.06 * abs(k)
	o.hry += 0.06 * k * s
	o.ear -= 0.16 * env(u, 0.04, 0.2, 0.82, 1)
end)

-- A yawn: a breath in with the head back, the jaw wide, the eyes shut, the ears back.
act("yawn", 1.8, function(o, u, t, s, S)
	local Y = Motion.YAWN
	o.jaw += track(Y.jaw, u)
	o.hrx += track(Y.head, u)
	o.bsq *= 1 + track(Y.sq, u)
	o.ear += 0.1 * bump(u, 0.2, 0.95)
	o.shut = o.shut or (u > 0.4 and u < 0.8)
end)

-- A wag: a burst of quick tail, the hips wiggling, the ears back, panting.
act("wag", 2.2, function(o, u, t, s, S)
	local p = env(u, 0, 0.1, 0.82, 1)
	o.wag += 0.4 * p
	o.bry += 0.035 * p * sin(t * WAG_F * 0.5)
	o.ear += 0.1 * p
	o.hrx -= 0.05 * p
	local pant = env(u, 0.1, 0.25, 0.75, 0.9)
	o.jaw += pant * (0.14 + 0.05 * sin(t * 15))
	o.bsq *= 1 + 0.012 * pant * sin(t * 15)
end)

-- A sniff at the ground: the head down and scanning, quick little twitches of the nose in bursts.
act("sniff", 2.6, function(o, u, t, s, S)
	local d = env(u, 0, 0.22, 0.74, 1)
	o.hrx += 0.42 * S.reach * d + 0.035 * d * max(0, sin(t * 6)) * sin(t * 34)
	o.htz += 0.03 * d
	o.brx += 0.04 * d
	o.hry += 0.16 * d * sin(TAU * u * 1.5) * s
	o.ear -= 0.08 * d
end)

-- A sniff at the air: the head up, the nose twitching, the ears up.
act("sniffair", 2.6, function(o, u, t, s, S)
	local d = env(u, 0, 0.22, 0.74, 1)
	o.hrx -= 0.34 * d - 0.03 * d * max(0, sin(t * 6)) * sin(t * 34)
	o.hry += 0.12 * d * sin(TAU * u) * s
	o.ear -= 0.15 * d
	o.jaw += 0.05 * d
end)

-- Shaking off: a squash first, then a fast twist of the whole body, the head a beat behind, the ears and tail
-- flapping, the eyes shut; a stretch at the end.
act("shake", 1.4, function(o, u, t, s, S)
	local b = env(u, 0.12, 0.22, 0.72, 0.86)
	o.bsq *= 1 - 0.04 * bump(u, 0, 0.18) + 0.02 * bump(u, 0.8, 1)
	o.bry += 0.2 * b * sin(t * 30)
	o.brz += 0.05 * b * sin(t * 30 + 1.2)
	o.hry -= 0.3 * b * sin(t * 30 - 1)
	o.hrz += 0.12 * b * sin(t * 30 - 0.4)
	o.earL += 0.55 * b * sin(t * 30 - 0.6)
	o.earR += 0.55 * b * sin(t * 30 + 0.9)
	o.tailRy += 0.35 * b * sin(t * 30 + 1.8)
	o.shut = o.shut or b > 0.5
end)

-- A play bow: the chest down on the forelegs reaching out in front, the rump and tail up and wagging, looking up; a
-- little bounce back up.
act("bow", 2.8, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.26, 0.66, 0.86)
	o.brx += 0.2 * p
	o.legF += 0.4 * p
	o.hrx -= 0.36 * p
	o.tailRx += 0.12 * p
	o.wag += 0.32 * p
	o.ear -= 0.1 * p
	o.jaw += 0.12 * p
	o.bty += 0.035 * bump(u, 0.84, 1)
end)

-- A cat's wash: a forepaw up, the head turned down to it, little licking nods, the eyes shut.
act("groom", 3.4, function(o, u, t, s, S)
	local p = env(u, 0.04, 0.2, 0.8, 0.96)
	local lick = env(u, 0.22, 0.28, 0.72, 0.78)
	local l = max(0, sin(t * 13))
	paw(o, s, 0.6 * p, 0.14 * p, 1.9 * p)
	o.hry += 0.3 * s * p
	o.hrx += 0.32 * p + 0.07 * lick * l
	o.hrz -= 0.12 * s * p
	o.brz += 0.03 * s * p
	o.jaw += 0.08 * lick * l
	o.ear += 0.06 * p
	o.shut = o.shut or lick > 0.5
end)

-- A stretch: forelegs out in front with the chest low and the rump up (a yawn in it), then the hind legs back.
act("stretch", 3.2, function(o, u, t, s, S)
	local a = env(u, 0.04, 0.22, 0.46, 0.58)
	local b = env(u, 0.5, 0.64, 0.8, 0.96)
	o.brx += 0.2 * a - 0.07 * b
	o.legF += 0.55 * a
	o.legH -= 0.45 * b
	o.btz += 0.05 * b
	o.hrx -= 0.18 * a
	o.tailRx += 0.3 * a
	o.jaw += 0.3 * bump(u, 0.1, 0.5)
	o.bsq *= 1 + 0.03 * a
	o.shut = o.shut or a > 0.6
end)

-- A slow blink, the head tipped a little, the ears easy.
act("blink", 1.8, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.25, 0.7, 0.95)
	o.hrz += 0.07 * s * p
	o.hrx += 0.05 * p
	o.ear += 0.08 * p
	o.shut = o.shut or (u > 0.22 and u < 0.68)
end)

-- A flick of the tail's tip (twice), the tail swishing over.
act("flick", 1.6, function(o, u, t, s, S)
	o.tailTip += 0.55 * bump(u, 0.08, 0.32) - 0.25 * bump(u, 0.3, 0.55) + 0.4 * bump(u, 0.6, 0.8)
	o.tailRy += 0.3 * s * env(u, 0.05, 0.3, 0.55, 0.9)
end)

-- A cat kneading: the forepaws pressing in turn, the eyes shut.
act("knead", 3, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.2, 0.8, 0.95)
	local w = sin(t * 7)
	o.liftLeg = if w > 0 then 2 else 1
	o.legUp += 0.045 * p * abs(w)
	o.legLift += 0.12 * p * abs(w)
	o.brx += 0.03 * p
	o.ear += 0.06 * p
	o.shut = o.shut or p > 0.5
end)

-- A slow sway from side to side, the head turning after it.
act("sway", 3.6, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.85, 1)
	local w = sin(TAU * 2 * u)
	o.brz += 0.06 * w * p
	o.bry += 0.03 * w * p
	o.hrz -= 0.04 * w * p
	o.hry += 0.1 * sin(TAU * 2 * u - 0.7) * p
end)

-- A scratch: a four-legged one's hind paw up under it scratching fast, the head leaning to it; anything else's hand
-- up to its head; the eyes shut, happy.
act("scratch", 2.8, function(o, u, t, s, S)
	local p = env(u, 0.04, 0.2, 0.78, 0.94)
	local sc = env(u, 0.2, 0.26, 0.72, 0.78)
	local w = sin(t * 26)
	if o.gait == "quad" then
		o.liftLeg = if s < 0 then 3 else 4
		o.legLift += (0.85 + 0.12 * w * sc) * p
		o.legUp += 0.08 * p
		o.hrz -= 0.25 * s * p
		o.hrx += 0.12 * p
		o.brz += 0.03 * s * p
		o.jaw += 0.1 * sc
	else
		if s < 0 then
			o.armL -= (2.5 + 0.12 * w * sc) * p
			o.armLz -= 0.3 * p
		else
			o.armR -= (2.5 + 0.12 * w * sc) * p
			o.armRz -= 0.3 * p
		end
		o.hrz -= 0.18 * s * p
	end
	o.shut = o.shut or sc > 0.5
end)

-- A howl: the head down first, then up high, the mouth open and the eyes shut, a quaver in it.
act("howl", 3.4, function(o, u, t, s, S)
	local p = env(u, 0.12, 0.32, 0.78, 0.95)
	o.hrx += 0.1 * bump(u, 0, 0.16) - 0.55 * p + 0.015 * p * sin(t * 22)
	o.brx -= 0.05 * p
	o.bsq *= 1 + 0.035 * p
	o.jaw += 0.28 * env(u, 0.24, 0.34, 0.74, 0.84)
	o.ear += 0.18 * p
	o.tailRx -= 0.1 * p
	o.shut = o.shut or p > 0.6
end)

-- A fox's pounce: a crouch, ears forward, the rump wiggling, then a leap up, nose up and then down onto the spot,
-- a squash as it lands.
act("pounce", 2.8, function(o, u, t, s, S)
	local crouch = env(u, 0.02, 0.25, 0.42, 0.5)
	local wig = env(u, 0.18, 0.24, 0.4, 0.46)
	local lu = (u - 0.44) / 0.4
	local air = if lu > 0 and lu < 1 then sin(PI * lu) else 0
	o.bsq *= 1 - 0.06 * crouch + 0.05 * bump(u, 0.42, 0.6) - 0.06 * bump(u, 0.78, 0.92)
	o.bty += -0.03 * crouch + 0.3 * air
	o.brx += 0.06 * crouch - 0.18 * bump(u, 0.44, 0.62) + 0.22 * bump(u, 0.6, 0.86)
	o.hrx += 0.15 * crouch + 0.25 * bump(u, 0.62, 0.92)
	o.bry += 0.06 * wig * sin(t * 20)
	o.ear -= 0.25 * env(u, 0.02, 0.15, 0.85, 1)
	o.tailTip += 0.25 * wig * sin(t * 24)
	o.legF += 0.35 * bump(u, 0.55, 0.85)
	o.legH -= 0.3 * bump(u, 0.44, 0.7)
	o.plant *= 1 - min(1, air * 4)
end)

-- A rabbit's nose twitching in bursts, an ear flicked, then the other.
act("twitch", 1.8, function(o, u, t, s, S)
	local p = env(u, 0, 0.1, 0.85, 1)
	local burst = p * max(0, sin(t * 5 + 1))
	o.hrx += 0.022 * burst * sin(t * 42)
	o.htz += 0.012 * burst * sin(t * 42 + 1)
	o.hry += 0.05 * s * p
	o.earL -= 0.12 * bump(u, 0.2, 0.45)
	o.earR -= 0.12 * bump(u, 0.45, 0.7)
end)

-- An ear flicked back fast, then the other, each turning as it goes.
act("earflick", 1.2, function(o, u, t, s, S)
	local a, b = track(FLICK1, u), track(FLICK2, u)
	if s < 0 then
		o.earL += 0.5 * a
		o.earYL += 0.3 * a
		o.earR += 0.4 * b
		o.earYR += 0.25 * b
	else
		o.earR += 0.5 * a
		o.earYR += 0.3 * a
		o.earL += 0.4 * b
		o.earYL += 0.25 * b
	end
end)

-- A rabbit's thump: a crouch, the ears up, a hind foot raised and brought down hard (twice), a jolt each time.
act("thump", 2, function(o, u, t, s, S)
	local crouch = env(u, 0.02, 0.25, 0.5, 0.6)
	local up = track(THUMP, u)
	o.liftLeg = if s < 0 then 1 else 2
	o.legUp += 0.1 * up
	o.legLift -= 0.15 * up
	o.bsq *= 1 - 0.035 * crouch - 0.05 * (bump(u, 0.55, 0.66) + 0.6 * bump(u, 0.81, 0.9))
	o.ear -= 0.25 * env(u, 0.02, 0.2, 0.85, 1)
	o.hrx -= 0.05 * crouch
end)

-- Sitting up tall to look about: the front up (a four-legged one's forelegs off the ground, hanging; paws held up),
-- the face kept level, the ears up, a look round while up.
act("situp", 3.4, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.28, 0.72, 0.92)
	o.brx -= 0.32 * p
	o.bty += 0.05 * p
	o.hrx += 0.26 * p
	o.bsq *= 1 + 0.05 * p
	o.ear -= 0.22 * p
	o.arm -= 0.5 * p
	o.free += p
	o.legF -= 0.2 * p
	o.hry += 0.4 * sin(TAU * u * 1.5) * env(u, 0.3, 0.4, 0.6, 0.7) * s
end)

-- A deer's ears swivelling, one back, then the other.
act("swivel", 2.6, function(o, u, t, s, S)
	local a = env(u, 0.05, 0.15, 0.4, 0.5)
	local b = env(u, 0.45, 0.55, 0.8, 0.92)
	if s < 0 then
		o.earYL += 0.9 * a
		o.earYR += 0.9 * b
	else
		o.earYR += 0.9 * a
		o.earYL += 0.9 * b
	end
	o.ear -= 0.08 * env(u, 0, 0.1, 0.9, 1)
	o.hry += 0.06 * s * (a - b)
end)

-- Grazing: the head down to the grass, chewing, the tail flicking, then up again and alert, the ears up.
act("graze", 4, function(o, u, t, s, S)
	local d = env(u, 0.03, 0.24, 0.66, 0.78)
	local chew = env(u, 0.24, 0.3, 0.62, 0.66)
	local al = env(u, 0.74, 0.8, 0.9, 1)
	o.hrx += 0.72 * S.reach * d - 0.12 * al
	o.brx += 0.06 * d
	o.htz += 0.02 * d
	o.jaw += 0.1 * chew * (0.5 + 0.5 * sin(t * 10))
	o.hry += 0.08 * chew * sin(t * 1.7)
	o.tailRy += 0.2 * chew * sin(t * 6)
	o.ear -= 0.25 * al
end)

-- Alert: the head up fast and still, the ears forward, a look to one side, the tail up; easing off slowly.
act("alert", 2.6, function(o, u, t, s, S)
	local p = env(u, 0, 0.1, 0.6, 0.95)
	o.hrx -= 0.22 * p
	o.ear -= 0.3 * p
	o.hry += 0.25 * s * env(u, 0.12, 0.25, 0.55, 0.8)
	o.tailRx += 0.3 * p
	o.bsq *= 1 + 0.02 * p
end)

-- An elephant's trunk swinging from side to side, then curled up toward its mouth.
act("trunk", 3.8, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.85, 1)
	o.tendrilRz += 0.4 * sin(TAU * u * 2) * p * s
	o.tendrilRx -= 0.6 * bump(u, 0.45, 0.85)
	o.tendrilTip += 0.9 * bump(u, 0.48, 0.88)
	o.hry += 0.06 * sin(TAU * u * 2 - 0.8) * p * s
end)

-- The trunk raised high to smell the air, the tip curled up.
act("trunkup", 3, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.3, 0.7, 0.95)
	o.tendrilRx -= 1.8 * p
	o.tendrilTip -= 0.5 * p
	o.tendrilRz += 0.1 * sin(t * 3) * p
	o.hrx -= 0.12 * p
	o.ear -= 0.08 * p
end)

-- Ears flapped to and fro.
act("earflap", 2.6, function(o, u, t, s, S)
	local p = env(u, 0, 0.12, 0.85, 1)
	local w = sin(t * 8)
	o.earYL += 0.45 * w * p
	o.earYR += 0.45 * w * p
	o.earL += 0.15 * w * p
	o.earR += 0.15 * w * p
end)

-- A stamp: the weight onto the other side, a foot raised, held, brought down hard, a jolt and a nod.
act("stomp", 2.2, function(o, u, t, s, S)
	local up = track(STOMP, u)
	local hit = bump(u, 0.54, 0.7)
	o.liftLeg = if s < 0 then 1 else 2
	o.legLift += 0.45 * up
	o.legUp += 0.14 * up
	o.brz += 0.035 * s * up
	o.bsq *= 1 - 0.05 * hit
	o.hrx += 0.1 * hit
end)

-- Pecking at the ground: up first, a fast strike, a slow return, a second smaller peck; the body after the head.
act("peck", 2, function(o, u, t, s, S)
	local h = track(Motion.PECK, u)
	o.hrx += h * S.reach
	o.brx += 0.25 * track(Motion.PECK, frac(u - 0.04))
	o.bsq *= 1 - 0.04 * max(0, h)
	o.tailRx += 0.15 * max(0, h)
	if h > 0.3 then
		o.jaw += 0.25
	end
end)

-- A bird's head bobbing three times, popped forward fast and drawn back slowly.
act("bob", 1.8, function(o, u, t, s, S)
	local q = frac(u * 3)
	local th = if q < 0.2 then ease(OUT, q / 0.2) else 1 - ease(SMOOTH, (q - 0.2) / 0.8)
	o.htz += 0.05 * th
	o.hrx += 0.06 * th
end)

-- Preening: the head turned far round and down into the wing (which lifts), little nibbles, the eyes shut.
act("preen", 3.6, function(o, u, t, s, S)
	local p = env(u, 0.04, 0.22, 0.78, 0.95)
	local nib = env(u, 0.22, 0.28, 0.72, 0.78)
	o.hry += 1.15 * s * p
	o.hrx += 0.4 * p + 0.06 * nib * sin(t * 18)
	o.hrz -= 0.15 * s * p
	if s < 0 then
		o.wingL += 0.3 * p
	else
		o.wingR += 0.3 * p
	end
	o.brz -= 0.03 * s * p
	o.tailRy += 0.15 * s * p
	o.jaw += 0.08 * nib * max(0, sin(t * 18))
	o.shut = o.shut or nib > 0.5
end)

-- Ruffling the feathers: a squash, then a quick shiver of the body puffed up, the wings out, the head shaking.
act("ruffle", 1.8, function(o, u, t, s, S)
	local b = env(u, 0.15, 0.25, 0.6, 0.8)
	local w = sin(t * 34)
	o.bsq *= 1 - 0.03 * bump(u, 0, 0.2) + 0.035 * b
	o.bry += 0.07 * b * w
	o.hrz += 0.14 * b * sin(t * 34 - 1)
	o.wingL += 0.12 * b
	o.wingR += 0.12 * b
	o.wingAmp += 0.06 * b
	o.tailRy += 0.15 * b * sin(t * 34 + 1)
	o.earL += 0.2 * b * w
	o.earR -= 0.2 * b * w
	o.shut = o.shut or b > 0.5
end)

-- Wings out and flapped, up on its toes, the head up.
act("flap", 2, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.2, 0.75, 0.95)
	o.wingAmp += 0.7 * p
	o.wingL += 0.5 * p
	o.wingR += 0.5 * p
	o.bsq *= 1 + 0.04 * p
	o.bty += 0.025 * p
	o.hrx -= 0.1 * p
	o.tailRx += 0.1 * p
	o.jaw += 0.15 * p
end)

-- An owl's head turned slowly far round, held (a slow blink), and back.
act("turn", 3.6, function(o, u, t, s, S)
	local k = track(TURN, u)
	o.hry += 1.75 * s * k
	o.hrz += 0.1 * s * k
	o.shut = o.shut or (u > 0.46 and u < 0.52)
end)

-- An owl peering: the head bobbing from side to side.
act("peer", 2.4, function(o, u, t, s, S)
	local p = env(u, 0, 0.12, 0.85, 1)
	o.hrz += 0.3 * sin(TAU * u * 2) * p * s
	o.hry += 0.12 * sin(TAU * u * 2 + 1.2) * p * s
	o.hrx -= 0.04 * p * (1 - cos(TAU * u * 4))
	o.bry += 0.03 * sin(TAU * u * 2) * p * s
end)

-- A waddle in place: rocking from foot to foot, the free foot lifting, the flippers out.
act("waddle", 2.6, function(o, u, t, s, S)
	local p = env(u, 0, 0.12, 0.88, 1)
	local w = sin(TAU * u * 3) * s
	o.brz += 0.09 * w * p
	o.bry += 0.04 * w * p
	o.hrz -= 0.05 * w * p
	o.liftLeg = if w > 0 then 2 else 1
	o.legUp += 0.05 * abs(w) * p
	o.wingL += 0.25 * p
	o.wingR += 0.25 * p
end)

-- A duck's tail waggled.
act("waggle", 1.4, function(o, u, t, s, S)
	local p = env(u, 0, 0.1, 0.8, 1)
	o.wag += 0.45 * p
	o.brz += 0.02 * p * sin(t * WAG_F)
end)

-- A frog's throat pulsing (the body in quick little squashes).
act("throat", 1.8, function(o, u, t, s, S)
	local p = env(u, 0, 0.1, 0.9, 1)
	o.bsq *= 1 + 0.03 * p * sin(t * 24)
	o.jaw += 0.03 * p * (0.5 + 0.5 * sin(t * 24))
end)

-- A little hop on the spot (the jump's keys, smaller): crouch, up, land, settle.
act("hopinplace", 1.4, function(o, u, t, s, S)
	local J = Motion.JUMP
	local ty = track(J.ty, u) * 0.4
	o.bty += ty
	o.bsq *= 1 + (track(J.sq, u) - 1) * 0.8
	o.brx += track(J.rx, u) * 0.5
	local lg = track(J.leg, u) * 0.7
	o.legF += lg
	o.legH += lg
	o.plant *= 1 - min(1, max(0, ty) * 12)
end)

-- A lizard's push-ups: three quick bobs of the front, the head a beat behind.
act("pushup", 1.8, function(o, u, t, s, S)
	local b = 0.5 - 0.5 * cos(TAU * 3 * u)
	o.bty += 0.05 * b
	o.brx -= 0.1 * b
	o.hrx -= 0.08 * (0.5 - 0.5 * cos(TAU * 3 * u - 0.6)) * env(u, 0, 0.05, 0.95, 1)
end)

-- A head snapped round to look, held, snapped back, a flick of the tongue.
act("headflick", 1.4, function(o, u, t, s, S)
	local k = track(HFLICK, u)
	o.hry += 0.45 * s * k
	o.hrx -= 0.06 * k
	o.jaw += 0.22 * bump(u, 0.24, 0.34)
end)

-- A flick of the tongue: drawn back, a look up, a snap of the jaw thrust forward, a gulp (a blink and a squash: frogs
-- blink to swallow).
act("tongue", 1.6, function(o, u, t, s, S)
	o.htz += 0.04 * bump(u, 0.3, 0.48) - 0.02 * bump(u, 0.05, 0.3)
	o.hrx -= 0.08 * env(u, 0.05, 0.2, 0.6, 0.8)
	o.jaw += 0.3 * bump(u, 0.32, 0.46)
	o.bsq *= 1 - 0.03 * bump(u, 0.58, 0.76)
	o.shut = o.shut or (u > 0.6 and u < 0.72)
end)

-- Basking: flattened a little, the head down, the eyes shut.
act("bask", 3.2, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.3, 0.7, 0.95)
	o.bsq *= 1 - 0.04 * p
	o.hrx += 0.06 * p
	o.shut = o.shut or (u > 0.3 and u < 0.7)
end)

-- A crab's claws snapping three times, raised a little.
act("snap", 1.6, function(o, u, t, s, S)
	local p = env(u, 0, 0.12, 0.85, 1)
	o.pincer = max(o.pincer, 0.8 * p * (0.5 - 0.5 * cos(TAU * 3 * u)))
	o.armL -= 0.2 * p
	o.armR -= 0.2 * p
end)

-- Claws up high and wide, open (a crab's show of strength), up on its legs, the stalks up.
act("raise", 2.4, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.22, 0.7, 0.92)
	o.armL -= 0.75 * p
	o.armR -= 0.75 * p
	o.armLz += 0.3 * p
	o.armRz += 0.3 * p
	o.pincer = max(o.pincer, 0.75 * p)
	o.bty += 0.03 * p
	o.brx -= 0.06 * p
	o.stalkSq += 0.15 * p
end)

-- A little shuffle to one side and back.
act("sidestep", 1.8, function(o, u, t, s, S)
	local p = bump(u, 0, 1)
	local w = sin(TAU * u * 3)
	o.btx += 0.05 * s * (bump(u, 0, 0.5) - bump(u, 0.5, 1))
	o.shuffle += p
	o.u += 2 * u
	o.bty += 0.015 * abs(w) * p
	o.brz += 0.02 * w * p
end)

-- Antennae waved, the head turning a little.
act("antennae", 2.2, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.85, 1)
	o.antAmp += 0.32 * p
	o.antRx -= 0.15 * p
	o.hry += 0.12 * sin(TAU * u) * p * s
end)

-- A beetle cleaning its antennae: the head tipped down to one side, the antennae drawn down and rubbed.
act("clean", 2.4, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.2, 0.8, 0.95)
	o.hrz -= 0.25 * s * p
	o.hrx += 0.15 * p
	o.antRx += 0.35 * p + 0.08 * p * sin(t * 16)
end)

-- A snail's stalks stretched out long, looking about, the body stretching after them.
act("stalks", 3.2, function(o, u, t, s, S)
	local p = env(u, 0.03, 0.3, 0.75, 0.97)
	o.stalkSq += 0.3 * p
	o.stalkTurn += 0.25 * sin(TAU * u * 1.5) * p * s
	o.stalkZ += 0.08 * p
	o.hrx -= 0.12 * p
	o.bsq *= 1 + 0.03 * p
end)

-- Drawn in fast (stalks short, the head back, claws in, the eyes shut), held, then out again slowly.
act("retract", 3.4, function(o, u, t, s, S)
	local p = env(u, 0.02, 0.12, 0.5, 0.95)
	o.stalkSq -= 0.3 * p
	o.htz -= 0.08 * p
	o.hrx += 0.15 * p
	o.bsq *= 1 - 0.05 * p
	o.armL += 0.5 * p
	o.armR += 0.5 * p
	o.shut = o.shut or p > 0.6
end)

-- A serpent's sway: the head in a slow figure of eight, the body and tail coiling after it.
act("coil", 3.8, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.85, 1)
	o.hry += 0.32 * sin(TAU * u * 2) * p * s
	o.hrz += 0.12 * sin(TAU * u * 4) * p
	o.bry += 0.07 * sin(TAU * u * 2 - 0.6) * p * s
	o.tailRy -= 0.3 * sin(TAU * u * 2 - 1.3) * p * s
	o.finAmp += 0.1 * p
end)

-- Drifting: rising and turning slowly, banking, the fins working.
act("drift", 3.2, function(o, u, t, s, S)
	local b = bump(u, 0, 1)
	o.bty += 0.1 * b
	o.bry += 0.3 * s * b
	o.brz += 0.06 * s * b
	o.brx -= 0.06 * sin(TAU * u) * s
	o.finAmp += 0.12 * b
end)

-- A dart: a fast flick of the tail, a burst forward and a drift back, the fins tucked then working.
act("dart", 1.4, function(o, u, t, s, S)
	o.tailRy += 0.55 * s * bump(u, 0, 0.22) - 0.4 * s * bump(u, 0.16, 0.42)
	o.btz += 0.12 * bump(u, 0.05, 1)
	o.brz -= 0.05 * s * bump(u, 0, 0.5)
	o.finZ -= 0.25 * bump(u, 0, 0.3)
	o.finAmp += 0.2 * bump(u, 0.3, 1)
end)

-- A fish's mouth gulping twice.
act("bubble", 1.6, function(o, u, t, s, S)
	o.jaw += 0.18 * (bump(u, 0.1, 0.35) + bump(u, 0.45, 0.7))
	o.hrx -= 0.04 * bump(u, 0.05, 0.75)
end)

-- Fins fluttered fast and flicked forward.
act("finflick", 1.2, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.8, 1)
	o.finAmp += 0.3 * p
	o.finY += 0.3 * bump(u, 0.1, 0.5)
	o.tailRy += 0.1 * s * p
end)

-- A jelly's (or an octopus's) pulse: the bell squashed fast, the tendrils flaring out, then stretched and gliding up,
-- the tendrils trailing in.
act("pulse", 2, function(o, u, t, s, S)
	local sq = bump(u, 0, 0.32)
	local st = bump(u, 0.24, 0.75)
	o.bsq *= 1 - 0.1 * sq + 0.06 * st
	o.hsq *= 1 - 0.05 * sq + 0.04 * st
	o.bty += 0.12 * bump(u, 0.1, 1)
	o.flare += 0.4 * sq - 0.18 * st
end)

-- Every tendril waving.
act("wave", 2.6, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.85, 1)
	o.tendrilAmp += 0.35 * p
	o.flare += 0.15 * sin(TAU * u * 2) * p
	o.hrz += 0.06 * sin(TAU * u * 2) * p * s
end)

-- A bounce on the stem (twice), the cap a beat behind, the arms flopping out.
act("bounce", 2, function(o, u, t, s, S)
	local p = env(u, 0, 0.1, 0.9, 1)
	local w = sin(TAU * u * 2)
	o.bsq *= 1 + 0.07 * w * p
	o.bty += 0.02 * (1 + w) * p
	o.hrx += 0.07 * sin(TAU * u * 2 - 1) * p
	o.hsq *= 1 - 0.05 * sin(TAU * u * 2 - 1.2) * p
	o.armLz += 0.1 * (1 + w) * p
	o.armRz += 0.1 * (1 + w) * p
end)

-- A flutter: the wings faster, up and round a little, the arms out.
act("flutter", 2, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.8, 1)
	o.wingAmp += 0.3 * p
	o.bty += 0.14 * bump(u, 0, 1)
	o.bry += 0.3 * s * bump(u, 0.1, 0.9)
	o.armLz += 0.2 * p
	o.armRz += 0.2 * p
	o.leg += 0.15 * p
end)

-- A little wave hello with one hand, the head tilted, a smile.
act("hello", 2.4, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.22, 0.75, 0.95)
	local w = env(u, 0.2, 0.26, 0.72, 0.78) * sin(t * 9)
	if s < 0 then
		o.armL -= 2.5 * p
		o.armLz += 0.25 * p + 0.35 * w
	else
		o.armR -= 2.5 * p
		o.armRz += 0.25 * p + 0.35 * w
	end
	o.hrz -= 0.12 * s * p
	o.jaw += 0.15 * p
end)

-- A seal's clap: the flippers forward and clapping, the head up barking, both ends raised.
act("clap", 2, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.2, 0.8, 0.95)
	local c = env(u, 0.2, 0.25, 0.75, 0.8)
	o.finY += 0.55 * p + 0.35 * c * sin(t * 16)
	o.finZ += 0.15 * p
	o.hrx -= 0.25 * p
	o.jaw += 0.25 * c * max(0, sin(t * 8))
	o.tailRx += 0.25 * p
	o.brx -= 0.05 * p
end)

-- A sea otter cracking a shell: both paws in front of its chest, striking down together.
act("crack", 2.4, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.2, 0.8, 0.95)
	local c = env(u, 0.2, 0.25, 0.75, 0.8)
	local hit = 0.35 * c * max(0, sin(t * 10))
	o.armL -= 1.2 * p - hit
	o.armR -= 1.2 * p - hit
	o.armLz -= 0.3 * p
	o.armRz -= 0.3 * p
	o.hrx += 0.18 * p
	o.bsq *= 1 - 0.015 * c * max(0, sin(t * 10))
end)

-- Rolling over onto one side and back.
act("roll", 3.2, function(o, u, t, s, S)
	local b = bump(u, 0, 1)
	o.brz += 0.3 * s * b
	o.hry += 0.15 * s * b
	o.finZ += 0.15 * b
end)

-- Wings folded in tight, then spread wide and held, the beat stilled.
act("fold", 2.8, function(o, u, t, s, S)
	local k = track(FOLD, u)
	o.wingL += 0.35 * k
	o.wingR += 0.35 * k
	o.wingAmp *= 1 - 0.85 * env(u, 0, 0.15, 0.85, 1)
	o.bsq *= 1 + 0.03 * max(0, k)
end)

-- One wing stretched out (and the leg on that side back), the body leaning away from it.
act("stretchwing", 2.8, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.3, 0.65, 0.92)
	if s < 0 then
		o.wingL += 0.6 * p
	else
		o.wingR += 0.6 * p
	end
	o.brz -= 0.04 * s * p
	o.hry += 0.15 * s * p
	o.liftLeg = if o.gait == "quad" then (if s < 0 then 3 else 4) else (if s < 0 then 1 else 2)
	o.legLift -= 0.35 * p
	o.legUp += 0.03 * p
end)

-- A golem rolling its shoulders, the head tipping to crack its neck.
act("shoulders", 3, function(o, u, t, s, S)
	local p = env(u, 0, 0.12, 0.88, 1)
	local a = TAU * u * 2
	o.armL -= 0.22 * sin(a) * p
	o.armLz += 0.15 * (0.5 - 0.5 * cos(a)) * p
	o.armR -= 0.22 * sin(a - 1.6) * p
	o.armRz += 0.15 * (0.5 - 0.5 * cos(a - 1.6)) * p
	o.bry += 0.05 * sin(a) * p
	o.hrz += 0.15 * sin(TAU * u) * p * s
end)

-- Beating its chest: the fists in turn on the chest, leaning back, the head up, hooting.
act("chest", 2.2, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.2, 0.8, 0.95)
	local b = env(u, 0.2, 0.25, 0.75, 0.8)
	local w = sin(t * 15)
	o.armL -= (1.3 + 0.3 * w * b) * p
	o.armR -= (1.3 - 0.3 * w * b) * p
	o.armLz -= 0.5 * p
	o.armRz -= 0.5 * p
	o.brx -= 0.08 * p
	o.hrx -= 0.22 * p
	o.bsq *= 1 + 0.03 * p
	o.jaw += 0.28 * b * max(0, sin(t * 7.5))
end)

-- Arms swung to and fro, the body twisting with them.
act("swing", 2.4, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.85, 1)
	local w = sin(t * 7)
	o.armL += 0.85 * w * p
	o.armR -= 0.85 * w * p
	o.bry += 0.1 * w * p
	o.bsq *= 1 - 0.015 * abs(w) * p
	o.jaw += 0.1 * p
end)

-- Curled up a little (head tucked, feet under, eyes shut), a peek out to one side, then uncurled.
act("curl", 3.6, function(o, u, t, s, S)
	local c = env(u, 0.02, 0.18, 0.72, 0.9)
	local peek = env(u, 0.4, 0.48, 0.6, 0.68)
	o.hrx += 0.6 * c - 0.35 * peek
	o.hry += 0.3 * s * peek
	o.brx += 0.1 * c
	o.bsq *= 1 - 0.07 * c
	o.legF -= 0.25 * c
	o.legH += 0.2 * c
	o.tailRx -= 0.3 * c
	o.ear += 0.3 * c
	o.shut = o.shut or (c > 0.6 and peek < 0.5)
end)

-- Pawing the ground with a forefoot (or a hand), the head down to look.
act("paw", 2.4, function(o, u, t, s, S)
	local p = env(u, 0.04, 0.18, 0.82, 0.96)
	local w = sin(t * 11)
	paw(o, s, (0.3 + 0.25 * w) * p, 0.05 * (0.5 + 0.5 * cos(t * 11)) * p, (0.8 + 0.4 * w) * p)
	o.hrx += 0.15 * p
	o.brz += 0.02 * s * p
end)

-- Digging: the claws (or forefeet) scraping in turn, the head down.
act("dig", 2.6, function(o, u, t, s, S)
	local p = env(u, 0.04, 0.16, 0.84, 0.96)
	local w = sin(t * 12)
	o.armL += (-0.45 + 0.5 * w) * p
	o.armR += (-0.45 - 0.5 * w) * p
	o.liftLeg = if w > 0 then 1 else 2
	o.legLift += 0.3 * abs(w) * p
	o.legUp += 0.04 * abs(w) * p
	o.hrx += 0.25 * p
	o.brx += 0.06 * p
	o.bry += 0.03 * w * p
end)

-- Washing the face: both paws up to it rubbing in little circles (a four-legged one, one forepaw), the eyes shut.
act("groomface", 2.8, function(o, u, t, s, S)
	local p = env(u, 0.04, 0.2, 0.8, 0.96)
	local r = env(u, 0.2, 0.26, 0.74, 0.8)
	local w = sin(t * 14)
	if o.gait == "quad" then
		paw(o, s, 1.1 * p, 0.05 * p, 0)
		o.hry += 0.2 * s * p
	else
		o.armL -= (1.8 + 0.16 * w * r) * p
		o.armR -= (1.8 + 0.16 * sin(t * 14 + 1.4) * r) * p
		o.armLz -= 0.35 * p
		o.armRz -= 0.35 * p
	end
	o.hrx += 0.16 * p + 0.04 * w * r
	o.shut = o.shut or r > 0.5
end)

-- Chewing the cud, content, a slow blink.
act("ruminate", 2.8, function(o, u, t, s, S)
	local p = env(u, 0, 0.1, 0.9, 1)
	o.jaw += 0.09 * p * (0.5 + 0.5 * sin(t * 9))
	o.hry += 0.025 * p * sin(t * 9 + 1)
	o.ear += 0.08 * p
	o.shut = o.shut or (u > 0.4 and u < 0.62)
end)

-- A head butt at nothing: rearing back, a lunge forward with the head down, back again, a little shake.
act("butt", 2.2, function(o, u, t, s, S)
	local back = env(u, 0.02, 0.28, 0.32, 0.4)
	local hit = env(u, 0.36, 0.42, 0.5, 0.75)
	o.btz += -0.04 * back + 0.06 * hit
	o.brx += -0.06 * back + 0.07 * hit
	o.hrx += -0.15 * back + 0.4 * hit
	o.hry += 0.08 * s * bump(u, 0.72, 1) * sin(t * 14)
	o.bsq *= 1 - 0.03 * back + 0.02 * hit
	o.ear += 0.12 * hit
end)

-- A horse tossing its head (a dip first), a snort, the tail swishing.
act("toss", 1.8, function(o, u, t, s, S)
	local k = bump(u, 0.12, 0.6)
	o.hrx += 0.08 * bump(u, 0, 0.16) - 0.35 * k
	o.hry += 0.18 * s * k
	o.hrz -= 0.15 * s * k
	o.bsq *= 1 + 0.03 * bump(u, 0.5, 0.8)
	o.jaw += 0.06 * bump(u, 0.55, 0.75)
	o.tailRy += 0.25 * bump(u, 0.3, 1) * sin(TAU * u * 2) * s
end)

-- A slow swish of the tail from side to side.
act("swish", 2.4, function(o, u, t, s, S)
	local p = env(u, 0, 0.12, 0.88, 1)
	o.tailRy += 0.45 * sin(TAU * u * 1.5) * p * s
	o.tailRx += 0.1 * p
	o.tailTip += 0.15 * sin(TAU * u * 1.5 - 1) * p
end)

-- A drake's snort: a deep breath in (the wings lifting with it), then out with the mouth open and the eyes shut.
act("snort", 2.2, function(o, u, t, s, S)
	local inb = env(u, 0.05, 0.4, 0.45, 0.55)
	local out = bump(u, 0.45, 0.8)
	o.bsq *= 1 + 0.04 * inb - 0.03 * out
	o.hrx -= 0.15 * inb - 0.1 * out
	o.jaw += 0.18 * out
	o.hry += 0.1 * s * out
	o.wingL += 0.1 * inb
	o.wingR += 0.1 * inb
	o.shut = o.shut or out > 0.6
end)

-- A turtle drawing its head into its shell fast, then out slowly.
act("tuck", 3.6, function(o, u, t, s, S)
	local p = env(u, 0.02, 0.12, 0.5, 0.92)
	o.htz -= 0.14 * p
	o.hrx += 0.1 * p
	o.bsq *= 1 - 0.02 * p
	o.shut = o.shut or p > 0.5
end)

-- The neck stretched out and up, looking round, a little gape.
act("stretchneck", 2.8, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.3, 0.7, 0.95)
	o.htz += 0.08 * p
	o.hrx -= 0.2 * p
	o.hry += 0.2 * s * sin(TAU * u) * p
	o.jaw += 0.06 * bump(u, 0.4, 0.6)
end)

-- A sea turtle rowing with its flippers.
act("paddle", 2.6, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.85, 1)
	o.legF += 0.45 * sin(t * 4.5) * p
	o.legH += 0.2 * sin(t * 4.5 + 1.2) * p
	o.hrx -= 0.06 * p
end)

-- A crocodile's gape: the jaws opened slowly wide, held, then shut with a snap.
act("gape", 3.6, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.4, 0.75, 0.84)
	o.jaw += 0.45 * p
	o.hrx -= 0.12 * p
	o.bsq *= 1 - 0.03 * bump(u, 0.82, 0.95)
end)

-- A chameleon rocking to and fro like a leaf in the wind, a quick look, the tail curling tighter.
act("rock", 3, function(o, u, t, s, S)
	local p = env(u, 0, 0.12, 0.88, 1)
	local w = sin(TAU * u * 3)
	o.btz += 0.03 * w * p
	o.brx += 0.04 * w * p
	o.hry += 0.2 * s * env(u, 0.3, 0.33, 0.6, 0.63)
	o.tailTip += 0.25 * p
end)

-- Floating: lifted a little as if in water, the tail undulating, the head tilting.
act("float", 3.4, function(o, u, t, s, S)
	local b = bump(u, 0, 1)
	o.bty += 0.03 * b
	o.tailAmp += 0.12 * b
	o.hrz += 0.1 * s * sin(TAU * u) * b
	o.brz += 0.03 * s * b
end)

-- A whale's spout: a deep breath in, rising, then out, the flippers lifting.
act("spout", 2.6, function(o, u, t, s, S)
	local inb = env(u, 0.05, 0.35, 0.4, 0.5)
	local out = bump(u, 0.42, 0.75)
	o.bsq *= 1 + 0.04 * inb - 0.04 * out
	o.hrx -= 0.1 * inb
	o.bty += 0.06 * inb
	o.finZ += 0.15 * out
	o.shut = o.shut or out > 0.5
end)

-- A ray's wings rippling bigger as it rises a little.
act("ripple", 2.4, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.85, 1)
	o.wingAmp += 0.3 * p
	o.bty += 0.06 * bump(u, 0, 1)
	o.brz += 0.04 * s * bump(u, 0, 1)
end)

-- A seahorse curling its tail tighter, then letting it go.
act("curltail", 2.6, function(o, u, t, s, S)
	local p = env(u, 0.05, 0.3, 0.7, 0.95)
	o.tailTip += 0.45 * p
	o.tailRx += 0.15 * p
	o.hrx += 0.05 * p
end)

-- A tree's crown and branches rustling as it sways.
act("rustle", 3.2, function(o, u, t, s, S)
	local p = env(u, 0, 0.15, 0.85, 1)
	local w = sin(TAU * u * 2)
	o.brz += 0.05 * w * p * s
	o.hrz += 0.09 * sin(TAU * u * 2 - 0.9) * p * s
	o.hrx += 0.03 * sin(t * 13) * p
	o.armLz += 0.12 * (0.5 + 0.5 * sin(TAU * u * 2 - 1.4)) * p
	o.armRz += 0.12 * (0.5 - 0.5 * sin(TAU * u * 2 - 1.4)) * p
end)

-- A bee's waggle dance.
act("dance", 2.4, function(o, u, t, s, S)
	local p = env(u, 0, 0.12, 0.88, 1)
	o.bry += 0.18 * sin(t * 22) * p
	o.btx += 0.08 * sin(TAU * u) * p * s
	o.bty += 0.04 * sin(TAU * u * 2) * p
	o.wingAmp += 0.15 * p
end)

-- A heron standing on one leg, the other folded up, the weight over the standing foot, a doze.
act("oneleg", 4.4, function(o, u, t, s, S)
	local p = env(u, 0.03, 0.18, 0.8, 0.95)
	o.liftLeg = if s < 0 then 1 else 2
	o.legLift -= 0.5 * p
	o.legUp += 0.16 * p
	o.brz += 0.04 * s * p
	o.hrx += 0.06 * p
	o.shut = o.shut or (u > 0.45 and u < 0.62)
end)

-- A heron's strike: the neck drawn out slowly and still, then a fast stab down and back up.
act("strike", 2.6, function(o, u, t, s, S)
	local reach = env(u, 0.03, 0.4, 0.5, 0.55)
	local hit = bump(u, 0.5, 0.75)
	o.htz += 0.06 * reach
	o.hrx += 0.15 * reach + 0.8 * hit * S.reach
	o.brx += 0.06 * reach + 0.15 * hit
	o.jaw += 0.25 * bump(u, 0.52, 0.66)
end)

-- The act playing at time t (seconds) for a driftling of `seed` and `tempo` in a style: its name (nil: none), its
-- progress u and the side it favours. Time is cut into windows of `every` seconds (its own, by the seed); most windows
-- play one act from the style's list at a point in it of the seed's choosing (not the act the window before played);
-- a few play none.
local QUIET = 0.14
local function pickAt(S: Style, tt: number, seed: number): (string?, number, number)
	local acts = S.acts
	local n = #acts
	if n == 0 then
		return nil, 0, 1
	end
	local per = S.every
	local x = tt / per + seed * 0.37
	local w = floor(x)
	local h = hash(w, seed)
	if h < QUIET then
		return nil, 0, 1
	end
	local i = 1 + floor(frac(h * 7.13) * n)
	if n > 1 then
		local hp = hash(w - 1, seed)
		if hp >= QUIET and 1 + floor(frac(hp * 7.13) * n) == i then
			i = i % n + 1
		end
	end
	local name = acts[i]
	local A = ACTS[name]
	if A == nil then
		return nil, 0, 1
	end
	local dur = min(A.dur, per - 0.8)
	local lt = (x - w) * per
	local s0 = 0.3 + frac(h * 13.7) * (per - 0.8 - dur)
	if lt <= s0 or lt >= s0 + dur then
		return nil, 0, 1
	end
	return name, (lt - s0) / dur, if frac(h * 3.31) < 0.5 then -1 else 1
end

function Motion.actAt(styleName: string?, t: number, seed: number, tempo: number?): (string?, number, number)
	return pickAt(Motion.style(styleName), t * (tempo or 1), seed)
end

-- (specs and previews) One act at u on a program, as the idle plays it.
function Motion.act(o: Prog, name: string, u: number, t: number, side: number, styleName: string?)
	local A = ACTS[name]
	if A then
		A.fn(o, u, t, side, Motion.style(styleName))
	end
end

------------------------------------------------------------------ the moods
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

-- the breath: in and out every `period` s, the body a little taller breathing in
local function breathe(o: Prog, t: number, depth: number, period: number?)
	local b = sin(TAU * t / (period or 3.1))
	o.bsq *= 1 + 0.022 * depth * b
	o.bty += 0.012 * depth * b
end

-- Standing about: its carriage, breathing, the weight shifting, a little life in the head, then an act now and then.
local function idle(o: Prog, t: number, tt: number, seed: number, S: Style, fly: boolean)
	breathe(o, t, S.breath, S.breathT)
	o.brx = S.lean
	o.brz = 0.035 * S.weight * track(Motion.WEIGHT, frac((t + seed * 3) / 8))
	o.hrz = -0.5 * o.brz
	o.hrx = S.head + 0.04 * sin(t * 1.3 + 0.5)
	o.ear, o.twitch = S.ear, S.twitch
	o.tailRx, o.tailTip, o.tailAmp, o.tailF, o.wag = S.tail, S.tip, S.sway, S.swayF, S.wag
	if S.fluke ~= 0 then
		o.tailRx += S.fluke * sin(t * 1.6)
	end
	o.armMode, o.arm = 0, S.arm + 0.08 * sin(t * 2)
	o.armLz, o.armRz = S.armOut, S.armOut
	o.wingRest, o.wingAmp, o.wingF = S.wing, S.wingAmp, S.wingF
	o.finAmp, o.finF = S.finAmp, S.finF
	o.small = S.small
	if fly then
		o.bty += S.hover * sin(TAU * t * S.hoverF) + (if S.wingAmp > 0.2 then 0.04 * sin(t * S.wingF - 0.9) else 0)
		if S.pulse > 0 then
			-- (a jelly's bell squeezing gently as it hangs there)
			local q = 0.5 + 0.5 * sin(t * 2.2)
			o.bsq *= 1 - 0.03 * S.pulse * q
			o.flare += 0.08 * S.pulse * q
		end
		o.legMode, o.leg = 6, 0.2
	else
		o.plant = 1
	end
	local name, u, s = pickAt(S, tt, seed)
	if name then
		(ACTS[name] :: Act).fn(o, u, tt, s, S)
	end
	if o.jaw > 0.12 then
		o.open = true
	end
end

-- Work out a mood's shared values at time t into `out`. Moods: "idle", "walk", "cheer", "hop", "attack" (k), "hurt"
-- and "ko" (by age), "hooray" (one jump from its start, then the happy pose held), the work moods "peck", "push",
-- "dip", "wave", "nap", and "rest" (the pose as built, eyes open). `style`: its manner (STYLE).
function Motion.program(mood: string, t: number, age: number, k: number, gait: string, tempo: number, seed: number, out: Prog, styleName: string?): Prog
	local o = out
	reset(o, mood, gait, t)
	local fly = gait == "fly"
	local tt = t * tempo
	if mood == "rest" then
		return o -- (the pose as built, eyes open: the portraits)
	end
	local S = STYLE[styleName or "default"] or DEF
	o.shut = blinking(t, seed)
	if mood == "walk" then
		-- one stride (two steps) every 1 / WALK.rate s at tempo 1
		local W = Motion.WALK
		local rate = W.rate * TAU
		local u = frac(tt * W.rate + seed * 0.13)
		o.u = u
		o.tailAmp, o.tailF = 0.3, rate * tempo
		o.armMode = 1
		o.wingAmp, o.wingF = 0.16, rate * tempo
		o.finAmp, o.finF = 0.3, rate * tempo
		-- (its carriage as it goes: the ears, the tail held up or low, a wag)
		o.ear, o.twitch, o.small = S.ear, S.twitch, max(1, S.small)
		o.tailRx, o.tailTip, o.wag = S.walkTail, S.tip, S.walkWag
		o.wingRest = S.wing
		o.arm = S.arm
		o.armLz, o.armRz = S.armOut, S.armOut
		if gait == "slither" then
			local b = 1 + S.bend
			o.brz = 0.1 * b * sin(TAU * u)
			o.hry = -0.5 * 0.1 * b * sin(TAU * (u - 0.08))
			o.tailAmp, o.tailF = 0.42 * b, rate * tempo
			o.legMode = 1
			if S.hump > 0 then
				-- a seal's humping crawl: the front lifting and the back after it, the flippers pushing
				local h = S.hump
				o.brx = 0.08 * h * sin(TAU * u * 2)
				o.bty = 0.03 * h * (0.5 + 0.5 * sin(TAU * u * 2 - 0.8))
				o.finY = 0.3 * h * sin(TAU * u * 2 + 0.6)
				o.hrx = S.head - 0.5 * o.brx
			end
		elseif gait == "scuttle" then
			o.legMode = 3
			-- (a crab's claws held up in front, bobbing with the steps; swung like a walker's arms they dipped to the
			-- ground mid-stride)
			o.armMode, o.arm = 2, -0.22 + 0.07 * sin(TAU * u * 3)
			o.bty = 0.03 * abs(sin(TAU * u * 3))
			o.brz = 0.03 * sin(TAU * u * 1.5)
			o.small = max(1.5, S.small)
		elseif fly then
			o.bty = 0.15 * sin(TAU * t * 0.4) + (if S.flyWing > 0.2 then 0.05 * sin(t * S.flyWingF * tempo - 0.9) else 0)
			o.brx = 0.14
			o.wingAmp, o.wingF = S.flyWing, S.flyWingF * tempo
			o.legMode = 6
			o.leg = 0.25
			o.tailAmp = 0.45
			if S.pulse > 0 then
				-- (a jelly or an octopus swims in pulses: the bell squeezed, the tendrils sweeping back after it)
				local q = 0.5 + 0.5 * sin(tt * 4.5)
				o.bsq = 1 - 0.07 * S.pulse * q
				o.bty += 0.04 * S.pulse * q
				o.flare = 0.25 * S.pulse * sin(tt * 4.5 + 1)
				o.tendrilRx = 0.3 * S.pulse
			end
			if S.fluke ~= 0 then
				o.tailRx += 1.6 * S.fluke * sin(tt * 3)
			end
		else
			-- walking (bipeds, four-legged ones and the hoppers too, their legs taking turns): the body highest as it
			-- passes over a planted leg (at a quarter of each foot's time on the ground past its plant), settling as
			-- the other comes down, the weight rolling onto the planted side (a waddle rolls far), the hips twisting
			-- with the stride, the head nodding a beat after the step and keeping level against the roll
			local over = cos(TAU * (2 * u - W.duty))
			local hv = S.heavy
			o.bty = W.bob * (1 + 0.6 * hv) * (0.5 + 0.5 * over)
			o.bsq = 1 + W.sq * (1 + 0.5 * hv) * over
			o.brz = W.roll * S.roll * sin(TAU * (u - 0.05))
			o.bry = W.twist * sin(TAU * u) + 0.12 * S.bend * sin(TAU * u + 0.5 * PI)
			o.brx = (if gait == "quad" then 0.04 else 0.06) + 0.5 * S.lean
			o.hrz = -0.6 * o.brz
			o.hrx = 0.04 * cos(TAU * (2 * u - W.duty - 0.12)) + S.nod * sin(TAU * 2 * u - 0.6) + 0.5 * S.head
			-- (a lizard's head keeps pointing ahead as its body bends; a heavy one's head swings slowly)
			o.hry = -0.8 * 0.12 * S.bend * sin(TAU * u + 0.5 * PI) + 0.05 * hv * sin(TAU * u - 0.6)
			o.tailRy = 0.25 * S.bend * sin(TAU * u - 0.3 * PI)
			if S.bob > 0 then
				-- (a bird's head bob: held back while the body goes on, then popped forward, every step)
				local q = frac(2 * u + 0.1)
				o.htz = S.bob * (if q < 0.25 then -1 + 2 * ease(OUT, q / 0.25) else 1 - 2 * ease(SMOOTH, (q - 0.25) / 0.75))
			end
			if S.roll > 1.8 then
				-- (a waddle: flippers out for balance)
				o.wingRest = S.wing + 0.2
			end
			o.legMode = if gait == "hop" then 7 else 1
		end
	elseif mood == "cheer" or mood == "hop" or mood == "hooray" then
		-- (a cheer jumps on and on; "hooray" jumps once, from the moment it starts, then holds the happy pose: the
		-- request of 2026-11-14, "make the pet jump only once instead of a few times after hatching")
		local cheer = mood ~= "hop"
		local period = (if cheer then 0.66 else 0.88) / tempo
		local u = if mood == "hooray" then math.clamp(age / period, 0, 1) else frac(t / period + seed * 0.21)
		local c = S.cheer
		if fly then
			o.bty = 0.25 * abs(sin(PI * u)) + (if mood == "hooray" then 0 else 0.04 * sin(t * 18))
			o.bsq = 1 + 0.06 * sin(TAU * u)
			o.wingAmp, o.wingF = 0.75, 18 * tempo
			o.legMode = 6
			o.leg = 0.3
		else
			local big = if cheer and c == "leap" then 1.35 else 1
			jump(o, u, (if cheer then 1.45 else 1.0) * big, if cheer then 1.05 * (if big > 1 then 1.1 else 1) else 0.9)
		end
		o.ear = S.ear
		o.tailRx, o.tailTip = S.tail, S.tip
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
			-- each plan's own cheer
			if c == "flap" then
				-- (wings out and beating hard as it jumps)
				o.wingAmp, o.wingRest = 0.8, S.wing + 0.3
			elseif c == "wag" then
				o.wag, o.tailRx = 0.5, S.tail + 0.15
			elseif c == "trumpet" then
				-- (the trunk raised high and curled up at the tip, the ears out and flapping)
				o.tendrilRx, o.tendrilTip = -2, -0.6
				o.earYL = 0.35 * sin(t * 9)
				o.earYR = o.earYL
			elseif c == "claws" then
				-- (claws up in front and wide, snapping fast)
				o.arm, o.armZ = -0.9 + 0.15 * sin(t * 11), 0
				o.armLz, o.armRz = 0.3, 0.3
				o.pincer = 0.5 + 0.4 * abs(sin(t * 14))
			elseif c == "wave" then
				o.tendrilAmp = 0.45
				o.flare = 0.1 + 0.25 * sin(t * 6)
			elseif c == "clap" then
				o.finY, o.finZ = 0.55 + 0.4 * sin(t * 16), 0.2
				o.tailRx = S.tail + 0.3
			elseif c == "bounce" then
				-- (the cap a beat behind the jump)
				o.hsq = 1 + 0.06 * sin(TAU * u - 1.2)
				o.hrx += 0.08 * sin(TAU * u - 1)
			elseif c == "flutter" then
				o.wingAmp = 0.85
			elseif c == "pound" then
				-- (fists pumped up in turn)
				o.armL = -0.35 * max(0, sin(t * 12))
				o.armR = -0.35 * max(0, -sin(t * 12))
			elseif c == "splash" then
				-- (a swimmer's leap: nose up rising, nose down falling, a big flick of the tail)
				o.brx = -0.35 * sin(TAU * u)
				o.wag = 0.5
			elseif c == "binky" then
				-- (a rabbit's twist in the air at the top of the jump)
				local tw = 0.45 * bump(u, 0.24, 0.7) * (if seed % 2 < 1 then 1 else -1)
				o.bry = tw
				o.hry = -0.6 * tw
			end
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
		-- the hit: squashed hard at once, wobbling back (an exaggerated squash that settles), flung back, shaking; the
		-- feet staying put
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
		o.plant = if fly then 0 else 1
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
		-- idle: its carriage, breathing, the weight shifting, twitching ears, a lazy tail, and its acts one at a time
		idle(o, t, tt, seed, S, fly)
	end
	return o
end

------------------------------------------------------------------ a bone's pose
-- A bone's pose under a program: its kind ("body", "head", "neck", "jaw", "ear", "arm", "leg", "tail", "wing",
-- "fin", "stalk", "pincer", "tendril", "antenna"), its side (-1 left, 1 right, 0 middle) and phase (a leg's place in the
-- stride 0..1, a tail or wing segment's number down the chain), and where its pivot is from the root's (dx, dz studs:
-- a leg's to keep its foot planted as the body pitches, a tendril's to spread out from the middle).
function Motion.bone(o: Prog, kind: string, side: number, ph: number, dx: number?, dz: number?): (number, number, number, number, number, number, number)
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
		-- (a droop folds the ear back as well as out; a perk, under 0, stands it up and forward; a swivel turns its
		-- opening out and back)
		local e = o.ear + (if side < 0 then o.earL else o.earR)
		local back = if e > 0 then -0.75 * e else -0.4 * e
		return back, side * (if side < 0 then o.earYL else o.earYR), -side * (a + (if e > 0 then 0.45 * e else e)), 0, 0, 0, o.earSq
	elseif kind == "arm" then
		local m = o.armMode
		local rx, rz = 0, 0
		if m == 0 then
			rx = o.arm + 0.04 * sin(t * 2 + side)
		elseif m == 1 then
			-- with the stride, against the legs, a beat behind them
			rx = o.arm + 0.42 * sin(TAU * (o.u + 0.14) + (if side > 0 then PI else 0))
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
		-- each arm's own turn on top (+ out from the body)
		if side < 0 then
			rx += o.armL
			rz += side * o.armLz
		else
			rx += o.armR
			rz += side * o.armRz
		end
		return rx, 0, rz, 0, 0, 0, 1
	elseif kind == "leg" then
		local m = o.legMode
		if m == 1 or m == 7 then
			-- a step (Motion.WALK): planted for `duty` of the stride, sweeping back at an even pace as the body goes
			-- over it (+rx: the foot behind the hip), then lifted and swung forward, eased, to plant again (a hopper's
			-- legs take turns by side)
			local W = Motion.WALK
			local p = frac(o.u + (if m == 7 then (if side < 0 then 0 else 0.5) else ph))
			if p < W.duty then
				return W.amp * (2 * p / W.duty - 1), 0, 0, 0, 0, 0, 1
			end
			local s = (p - W.duty) / (1 - W.duty)
			local e = s * s * (3 - 2 * s)
			return W.amp * (1 - 2 * e), 0, 0, 0, W.lift * sin(PI * s), 0, 1
		elseif m == 4 then
			-- pacing in place: the foot pushing back on the ground, lifting on the way forward
			local w = TAU * (o.u + ph)
			return -0.36 * sin(w), 0, 0, 0, 0.08 * max(0, cos(w)), 0, 1
		elseif m == 2 then
			-- (JUMP.leg is + forward)
			return -o.leg * (if side < 0 then 1 else 0.92), 0, 0, 0, 0, 0, 1
		elseif m == 3 then
			local s = sin(TAU * (o.u * 1.5 + ph))
			return 0, 0, side * 0.26 * s, 0, 0.06 * max(0, s), 0, 1
		elseif m == 5 then
			return o.leg, 0, 0, 0, 0, 0, 1
		elseif m == 6 then
			return o.leg + 0.12 * sin(t * 3 + side), 0, 0, 0, 0, 0, 1
		end
		-- standing: a four-legged one's forelegs (left fore at phase 0, right fore at 0.5, the hind legs the other way
		-- round: DriftPlans' QUAD) and hind legs by their own turns; any other's legs count as fore; one leg lifted; the
		-- feet planted against the body's pitch and rise (`plant`: turned back upright, and shifted by how far the
		-- body's pitch lifts or drops the hip, from its place along the body)
		local fore = o.gait ~= "quad" or ((side < 0) == (ph < 0.25))
		local rx = if fore then -o.legF else -o.legH
		local rz, ty = 0, 0
		if o.shuffle ~= 0 then
			local s = sin(TAU * (o.u * 1.5 + ph))
			rz = side * 0.26 * s * o.shuffle
			ty = 0.06 * max(0, s) * o.shuffle
		end
		if o.liftLeg ~= 0 and (if fore then 1 else 3) + (if side > 0 then 1 else 0) == o.liftLeg then
			rx -= o.legLift
			ty += o.legUp
		end
		local pl = o.plant * (if fore and o.gait == "quad" then 1 - min(1, o.free) else 1)
		if pl ~= 0 then
			rx -= o.brx * pl
			ty += ((dz or 0) * sin(o.brx) - o.bty) * pl
		end
		return rx, 0, rz, 0, ty, 0, 1
	elseif kind == "tail" then
		-- each segment a little later than the one before, the later ones less (a wave down it); a wag on top; the tip
		-- curled
		local late = ph >= 2
		local seg = if late then 0.55 else 1
		local ry = o.tailAmp * seg * sin(t * o.tailF - ph * 0.8 + side) + (o.tailCurl + o.tailRy) * seg
		if o.wag ~= 0 then
			ry += o.wag * (if late then 0.7 else 1) * sin(t * WAG_F - ph * 1.1)
		end
		return o.tailRx * seg + (if late then o.tailTip else 0), ry, 0, 0, 0, 0, 1
	elseif kind == "wing" then
		-- a flap: the downstroke quicker than the upstroke, each outer segment a little later
		local w = t * o.wingF - ph * 0.6
		local f = sin(w)
		f = if f < 0 then -(-f) ^ 0.7 else f ^ 1.3
		return 0, 0, side * (o.wingRest + o.wingAmp * f + (if side < 0 then o.wingL else o.wingR)), 0, 0, 0, 1
	elseif kind == "fin" then
		local a = o.finAmp * sin(t * o.finF + side)
		if side ~= 0 then
			return 0, -side * o.finY, side * (a + o.finZ), 0, 0, 0, 1
		end
		return 0, a, 0, 0, 0, 0, 1
	elseif kind == "stalk" then
		local s = o.small
		return -0.5 * o.droop + o.stalkX, 0, side * (0.16 * s * sin(t * 2.3 * s + side) + o.stalkZ) + o.stalkTurn, 0, 0, 0, o.stalkSq
	elseif kind == "pincer" then
		local open = max(o.pincer, 0.24 * max(0, sin(t * 2.4 + side)))
		return -open, 0, 0, 0, 0, 0, 1
	elseif kind == "tendril" then
		local s = o.small
		local late = ph % 1 > 0
		local amp = 0.2 * s * (if late then 0.6 else 1)
		local rx = amp * sin(t * 3 * s + ph) + 0.5 * o.droop + (if late then o.tendrilTip else o.tendrilRx)
		local rz = 0.1 * sin(t * 2 + ph * 1.7) + o.tendrilRz
		if o.tendrilAmp ~= 0 then
			rx += o.tendrilAmp * (if late then 1.3 else 1) * sin(t * TEND_F + ph * 1.3)
		end
		if o.flare ~= 0 then
			-- (spread out from the middle: tipped away from the body's axis)
			local x, z = dx or 0, dz or 0
			local r = sqrt(x * x + z * z)
			if r > 1e-3 then
				local f = o.flare * (if late then 0.6 else 1)
				rx -= f * z / r
				rz += f * x / r
			end
		end
		return rx, 0, rz, 0, 0, 0, 1
	elseif kind == "antenna" then
		local s = o.small
		local rx = 0.17 * s * sin(t * 4 * s + side) + 0.45 * o.droop + o.antRx
		if o.antAmp ~= 0 then
			rx += o.antAmp * sin(t * ANT_F + side * 1.3)
		end
		return rx, 0, 0, 0, 0, 0, 1
	end
	return 0, 0, 0, 0, 0, 0, 1
end

return Motion
