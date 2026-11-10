--!strict
-- An expedition on screen (GAME_DESIGN 7; docs/ARCHITECTURE.md 10.9): the island's 3D stage (UI/MicroStage: its
-- kind's set laid out by its seed, drawn full screen by the pixel filter) with the party on the left (the founder,
-- villagers as their own chibis, driftlings as their 3D models) and, in a battle, the wild driftlings on the right.
-- Right after the sailing cutscene (UI/Voyage, `sail`) the expedition boat glides in to the shore and the party hops
-- off it; reopened later, they drop in from above. Along the top the island's path
-- of stops (the landing, loot, chests, battles, a rest, the guardian) and the loot gathered; along the bottom the
-- party's cards with their health and the buttons: Go on (exp.next) and Sail home (exp.home) between stops; Fight,
-- Guard, Treat (a wild one picked by tapping its card) and Flee in a battle (exp.act). A round's events (Logic/Battle)
-- play back one by one: lunges, flashes, numbers, skills' names, heals, shields, a treat's hearts, knock-outs. A win
-- shows the experience, shells and level-ups; a new friend joins with confetti; the guardian's fall charts the
-- island. The screen can be closed (Back to island) while the expedition waits: the HUD's card brings it back. A
-- curtain covers the screen while the stage's picture bakes.
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Creatures = require(ReplicatedStorage.Shared.Data.Creatures)
local Expedition = require(ReplicatedStorage.Shared.Logic.Expedition)
local Battle = require(ReplicatedStorage.Shared.Logic.Battle)
local Skills = require(ReplicatedStorage.Shared.Data.Skills)
local Islets = require(ReplicatedStorage.Shared.Data.Islets)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local DayLight = require(script.Parent.Parent.Controllers.DayLight)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local MicroStage = require(script.Parent.MicroStage)
local Words = require(script.Parent.Words)
local Voyage = require(script.Parent.Voyage)
local BoatSpec = require(ReplicatedStorage.Shared.Models.BoatSpec)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)

local ExpeditionUI = {}
ExpeditionUI.Changed = Util.Signal() :: Types.Signal<boolean>

local HEAD_H = 25 -- the header: its words, then a trim of planks along its bottom (3 px)
local FOOT_H = 45 -- the footer: a trim of planks along its top (3 px), then the party and the buttons
local CARD_W = 80
local STEP = 0.5 -- seconds an event plays

-- Someone on the stage: the founder, a villager (a rival chibi), a driftling or a wild one (a 3D model).
type Actor = {
	key: string,
	foe: boolean,
	founder: boolean,
	rival: MicroStage.Rival?,
	thing: MicroModels.Thing?,
	u: number,
	v: number,
	du: number,
	dy: number,
	yaw: number,
	action: string,
	until_: number,
	ko: boolean,
	gone: boolean,
	enterAt: number,
	ph: number,
	big: boolean,
	deck: number, -- the party's place on the arriving boat's deck (0: none: dropped in)
	dv: number, -- off its place across the stage (a dash to a foe)
	move: Move?, -- what it is doing in a battle (an attack, a knock-back, a cheer...)
	scale0: number, -- its built size (the guardian 1.6)
	sqKey: string, -- the squash it is drawn at now
}

-- A battle move (GAME_DESIGN 7's expressive battles): its kind, when it began, how long it lasts and the gap it
-- closes or the way it is knocked (studs along and across the stage).
type Move = { kind: string, t0: number, dur: number, gu: number, gv: number }
-- What a move does to its actor at a moment.
type MoveFrame = { du: number, dv: number, dy: number, tilt: CFrame, sq: Vector3, spin: number, action: string, k: number, mood: string, speed: number }

-- The shown health (the events move it; the view's numbers settle it after a round).
type Bar = { hp: number, maxHp: number, name: string, lvl: number, card: Frame?, fill: Frame?, label: TextLabel?, w: number }

local isOpen = false
local stage: MicroStage.Stage? = nil
local root: Frame? = nil
local actors: { [string]: Actor } = {}
local bars: { [string]: Bar } = {}
local busy = false
local beat: RBXScriptConnection? = nil
local keys: RBXScriptConnection? = nil
local opened = 0
local lifted = false
local liftDelay = 0 -- seconds from opening to the curtain lifting
local stageWait: number? = nil -- the previews' longer wait for the picture (debugWait; the fake engine bakes slowly)
local isle: Types.Isle? = nil
-- the boat's arrival at the shore after the cutscene: the ship and when it set off (the party hops off after)
local arriving = false
local ship: MicroModels.Thing? = nil
local SHIP_U, SHIP_V, SHIP_FROM = -21, 11, -34 -- in the shallows off the floor's front-left edge (a level-2 boat)
local SHIP_IN = 1.0 -- seconds it glides in
local HOP_T, LAND, RUN = 0.4, 3.5, 12 -- a hop off (seconds, studs onto the shore), then a run to the place (studs/s)
local WATER = -0.45 -- the sea's surface on the stage (from the floor's top)
-- where the party stands on deck (along the bow: u; across: v), the founder first (UI/Voyage's deck)
local DECK_SPOTS = { { -0.1, 0, 0 }, { 0.9, -0.75, 0 }, { 0.9, 0.75, 0 }, { 1.75, 0, 0.5 } }
local shipU0 = SHIP_U -- the arriving boat's mooring (a longer boat a little further out)
local deckH = 0.625 -- its deck over the sea
local closing = false
local lastNode = 0
local foeKey = "" -- the battle's foes shown (rebuilt when they change)
local pendingOpen = 0 -- os.clock until which the screen opens as soon as the view has the expedition (just started)
-- going on by itself (GAME_DESIGN 7: "no need to click on go on"): at a stop with nothing to answer, the party walks on
-- to the next one after AUTO_GO seconds; a won battle's card goes after AUTO_CARD
local AUTO_GO = 1.8
local AUTO_CARD = 3
local idleSince: number? = nil
local autoFill: Frame? = nil
local autoW = 0
local PATH_AHEAD = 7 -- the header shows the path from a stop back to this many ahead (it never ends)
-- the timed battle (GAME_DESIGN 7: "the characters have a timer above their heads that is shown as a bar, and will
-- attack or use its skill once a timer is done"): the server runs it; here the timers as it last told (`gaugeG` at
-- `gaugeAt`, the action holding them then `gaugeLock`, paused or not) run on between its messages, as do the party's
-- skill points; its actions play back one message after another (`playQueue`). The health shown follows the events
-- (`shownHp`: the view's numbers come at the battle's end).
local gaugeG: { [string]: number } = {}
local gaugeAt = 0
local gaugeLock = 0
local gaugeCrowd = 1 -- how much slower the timers fill in this crowd (the server's Battle.crowd)
local gaugePaused = true
local spNow = 0
local snacksLeft = 0
local shownHp: { [string]: number } = {}
local timerBars: { [string]: { frame: Frame, fill: Frame, w: number } } = {}
local playQueue: { { [string]: any } } = {}
local pumping = false
local runAt: number? = nil -- when to let the battle run (its wild ones landed, the screen lifted)
-- aiming a snack or a skill (GAME_DESIGN 7: "using a snack greys and pauses the fighting, and allows you to select an
-- enemy, with your leader having an arrow marked on the floor to whoever you are selecting in a circle"; the skill
-- window "act[s] like the snack interface"): who acts, the skill, which side it aims at ("foe", "ally", "down" or
-- "none"), the target picked. The picture greys (DayLight.hold) and the battle pauses while aiming or choosing.
type Aim = { kind: string, who: string, skill: string?, side: string, target: string? }
local aim: Aim? = nil
local skillMenu = false
local aimMark: MicroModels.Thing? = nil -- the ring on the floor round the one acting
local aimPath: MicroModels.Thing? = nil -- the arrow from that ring all the way to the pick
local aimRing: MicroModels.Thing? = nil -- the ring under the pick
local aimPointer: GuiObject? = nil -- the little arrow over the target's head
local aimEndU: number? = nil -- where the arrow's end is now (stage u, v): it glides to the pick
local aimEndV = 0
local aimRingR = 0 -- the pick's ring's radius now (it pops on a new pick)
local aimRingFor: string? = nil
local aimClock = 0
local pointerConns: { RBXScriptConnection } = {}
local GREY: PixelRenderer.Grade = { mr = 0.72, mg = 0.72, mb = 0.76, lift = 4, sat = 0.1, lamps = 0 }

local refresh: () -> () = function() end
local pickTarget: (key: string?) -> () = function(_key: string?) end
local closeNow: () -> () = function() end

local function view(): Types.ClientView?
	return StateClient.view()
end

local function exp(): Types.Expedition?
	local v = view()
	return if v then v.exp else nil
end

local function hideWorldUI(on: boolean)
	for _, name in { "Hud", "World" } do
		UIKit.root(name).Enabled = not on
	end
	pcall(function()
		GuiService.TouchControlsEnabled = not on
	end)
end

------------------------------------------------------------------ the actors
local PARTY_SPOTS = { { -6, -1 }, { -9, -4.5 }, { -9, 2.5 }, { -12, -1 } }
local FOE_SPOTS = { { 6, -1 }, { 9, -4.5 }, { 9, 2.5 } }

local function actorAt(a: Actor): Vector3
	local st = stage
	if st == nil then
		-- (the screen closed while an action was still playing: it finishes on nothing)
		return Vector3.zero
	end
	return st.at(a.u + a.du, a.v + a.dv, a.dy)
end

-- How tall someone stands (studs over its feet): people about 4.75 (the hair's top), a driftling its model's height
-- at its size; the timers, the pointer and the floating words go just over it.
local PERSON_H = 4.75
local function headOf(a: Actor): number
	local t = a.thing
	if t then
		return (t :: MicroModels.Thing).h * a.scale0
	end
	return PERSON_H
end

local function removeActor(key: string)
	local a = actors[key]
	local st = stage
	if a == nil or st == nil then
		return
	end
	if a.thing then
		st.remove(a.thing :: MicroModels.Thing)
	end
	if a.rival then
		(a.rival :: MicroStage.Rival).hide()
	end
	actors[key] = nil
end

local function newActor(key: string, foe: boolean, spot: { number }): Actor
	return {
		key = key,
		foe = foe,
		founder = key == "f",
		rival = nil,
		thing = nil,
		u = spot[1],
		v = spot[2],
		du = 0,
		dy = 0,
		yaw = if foe then MicroStage.FACE_LEFT else MicroStage.FACE_RIGHT,
		action = "stand",
		until_ = 0,
		ko = false,
		gone = false,
		enterAt = os.clock(),
		ph = math.random() * 4,
		big = false,
		deck = 0,
		dv = 0,
		move = nil,
		scale0 = 1,
		sqKey = "",
	}
end

local function driftling(st: MicroStage.Stage, sp: string, big: boolean): MicroModels.Thing
	local d = Creatures.byId[sp]
	local t = MicroModels.driftling(if d then d.shape else "blob", if d then d.body else "steel", if d then d.accent else "steel_dark")
	if big then
		MicroModels.scale(t, Vector3.one * 1.6)
	end
	return st.adopt(t, if big then 1.6 else 1)
end

-- The party on the stage, from the expedition's fighters (once: they stay while the screen is open).
local function buildParty(e: Types.Expedition)
	local st = stage :: MicroStage.Stage
	local delay = 0
	for i, f in e.party do
		if actors[f.key] then
			continue
		end
		local a = newActor(f.key, false, PARTY_SPOTS[i] or PARTY_SPOTS[#PARTY_SPOTS])
		if f.kind == "villager" and f.look then
			delay += 0.12
			a.rival = st.rival(f.look :: Types.Look, delay)
		elseif f.kind == "pal" and f.sp then
			a.thing = driftling(st, f.sp :: string, false)
			a.dy = if arriving then 0 else 8
		end
		if arriving then
			a.deck = i
		end
		actors[f.key] = a
	end
end

-- The battle's wild ones drop in from above (rebuilt when the battle's foes change).
local function buildFoes(e: Types.Expedition)
	local b = e.battle
	local key = ""
	if b then
		for _, f in b.foes do
			key ..= f.key .. (f.sp or "") .. ","
		end
	end
	if key == foeKey then
		return
	end
	-- an action still playing (a snack's throw at a wild one the server has already befriended, the last blow of a
	-- battle already won) keeps the wild ones it shows: the view's new line-up (the battle over, the next one) waits
	-- till the playback is done, which lays the screen out again (`enqueue`)
	if pumping and foeKey ~= "" then
		return
	end
	foeKey = key
	for k, a in actors do
		if a.foe then
			removeActor(k)
		end
	end
	if b == nil then
		return
	end
	local st = stage :: MicroStage.Stage
	for i, f in b.foes do
		if f.hp <= 0 then
			continue
		end
		local a = newActor(f.key, true, FOE_SPOTS[i] or FOE_SPOTS[1])
		a.big = b.boss and i == 1
		a.scale0 = if a.big then 1.6 else 1
		a.thing = driftling(st, f.sp or "pebblit", a.big)
		a.dy = 10
		a.enterAt = os.clock() + (i - 1) * 0.15
		actors[f.key] = a
	end
	Audio.play(if b.boss then "drumroll" else "pop")
end

local function act(a: Actor, action: string, seconds: number)
	a.action = action
	a.until_ = os.clock() + seconds
end

------------------------------------------------------------------ the moves
-- Each attack winds up (crouching back, squashed), dashes right up to its target (stretched, kicking up dust), strikes
-- (a lunge and a swing, a bite or a ram leaning in) and hops back home; the hit freezes the action for a few frames
-- (hit-stop) and shakes the picture; the one hit is knocked back leaning away (or sent flying, spinning, when it is
-- down). Skills have their own: a bash leaps high and slams down, quick strikes three times in a blur, a zap charges
-- up where it stands and throws a bolt. Times in seconds; IMPACTS are the moments the blows land.
local MOVES: { [string]: number } = { attack = 0.92, bash = 1.15, quick = 0.85, zap = 0.8, hurt = 0.45, ko = 0.75, guard = 0.6, cast = 0.7, throw = 0.5, refuse = 0.7, happy = 1.0, flee = 0.7, stumble = 0.9, victory = 1.6 }
local IMPACTS: { [string]: { number } } = { attack = { 0.44 }, bash = { 0.64 }, quick = { 0.24, 0.38, 0.52 }, zap = { 0.52 } }
local REACH = 2.25 -- an attacker stops this far short of its target (studs)
local freezeUntil = 0
local shakeUntil, shakeAmp = 0, 0

local function ease(x: number): number
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) * (1 - x)
end
local function easeIn(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x
end
local function phase(e: number, a: number, b: number): number
	return math.clamp((e - a) / (b - a), 0, 1)
end

local function startMove(a: Actor, kind: string, other: Actor?)
	local gu, gv = 0, 0
	if other then
		local du, dv = other.u - a.u, other.v - a.v
		local d = math.sqrt(du * du + dv * dv)
		if kind == "hurt" or kind == "ko" then
			-- knocked away from the one who hit it
			gu, gv = if d > 0 then -du / d else (if a.foe then 1 else -1), if d > 0 then -dv / d else 0
		elseif d > REACH then
			gu, gv = du * (d - REACH) / d, dv * (d - REACH) / d
		end
	end
	a.move = { kind = kind, t0 = os.clock(), dur = MOVES[kind] or 0.5, gu = gu, gv = gv }
end

-- The stage shakes by whole art px for a moment; the action freezes (a hit's weight).
local function shake(amp: number, seconds: number)
	shakeAmp = math.max(if os.clock() < shakeUntil then shakeAmp else 0, amp)
	shakeUntil = os.clock() + seconds
end
local function freeze(seconds: number)
	freezeUntil = math.max(freezeUntil, os.clock() + seconds)
end

local SQ1 = Vector3.one
local shaking = false
local function frameOf(a: Actor, mv: Move, e: number): MoveFrame
	local dir = if a.foe then -1 else 1
	local f: MoveFrame = { du = 0, dv = 0, dy = 0, tilt = CFrame.identity, sq = SQ1, spin = 0, action = "stand", k = 0, mood = "idle", speed = 0 }
	local kind = mv.kind
	local gu, gv = mv.gu, mv.gv
	if kind == "attack" or kind == "quick" then
		local w1 = if kind == "quick" then 0.08 else 0.2
		local d1 = if kind == "quick" then 0.18 else 0.36
		local s1 = if kind == "quick" then 0.6 else 0.5
		local r0 = if kind == "quick" then 0.6 else 0.62
		if e < w1 then
			local k = ease(phase(e, 0, w1))
			f.du, f.sq, f.action, f.mood = -0.75 * dir * k, Vector3.new(1 + 0.18 * k, 1 - 0.18 * k, 1 + 0.18 * k), "windup", "attack"
			f.tilt = CFrame.Angles(math.rad(-12) * k, 0, 0)
		elseif e < d1 then
			local k = easeIn(phase(e, w1, d1))
			f.du, f.dv = -0.75 * dir + (gu + 0.75 * dir) * k, gv * k
			f.dy = math.sin(k * math.pi) * 0.6
			f.sq, f.action, f.speed, f.mood, f.k = Vector3.new(0.85, 1.15, 0.85), "run", 30, "attack", 0.3
			f.tilt = CFrame.Angles(math.rad(15), 0, 0)
		elseif e < s1 then
			local k = phase(e, d1, s1)
			local jab = if kind == "quick" then math.abs(math.sin(k * math.pi * 3)) else math.sin(k * math.pi)
			f.du, f.dv = gu + dir * 0.4 * jab, gv
			f.action, f.k, f.mood = "strike", if kind == "quick" then (k * 3) % 1 else k, "attack"
			f.tilt = CFrame.Angles(math.rad(28) * jab, 0, 0)
			f.sq = Vector3.new(1 + 0.2 * jab, 1 - 0.15 * jab, 1 + 0.2 * jab)
		elseif e < r0 then
			f.du, f.dv, f.action, f.mood, f.k = gu - dir * 0.3, gv, "strike", "attack", 1
		else
			local k = ease(phase(e, r0, mv.dur))
			f.du, f.dv = (gu - dir * 0.3) * (1 - k), gv * (1 - k)
			f.dy = math.sin(k * math.pi) * 1.25
			f.action = if k < 0.95 then "jump" else "stand"
		end
	elseif kind == "bash" then
		if e < 0.3 then
			local k = ease(phase(e, 0, 0.3))
			f.du, f.sq, f.action, f.mood = -0.9 * dir * k, Vector3.new(1 + 0.3 * k, 1 - 0.3 * k, 1 + 0.3 * k), "windup", "attack"
			f.tilt = CFrame.Angles(math.rad(-15) * k, 0, 0)
		elseif e < 0.64 then
			local k = phase(e, 0.3, 0.64)
			f.du, f.dv = -0.9 * dir + (gu + 0.9 * dir) * k, gv * k
			f.dy = math.sin(k * math.pi) * 4.5 * (1 - k * 0.15)
			f.sq, f.action, f.mood, f.k = Vector3.new(0.8, 1.25, 0.8), "jump", "attack", 0.5
			f.tilt = CFrame.Angles(math.rad(30) * k, 0, 0)
		elseif e < 0.8 then
			local k = phase(e, 0.64, 0.8)
			f.du, f.dv = gu, gv
			f.sq = Vector3.new(1.3 - 0.3 * k, 0.7 + 0.3 * k, 1.3 - 0.3 * k)
			f.action, f.mood, f.k = "strike", "attack", 1
		else
			local k = ease(phase(e, 0.8, mv.dur))
			f.du, f.dv = gu * (1 - k), gv * (1 - k)
			f.dy = math.sin(k * math.pi) * 1.5
			f.action = if k < 0.95 then "jump" else "stand"
		end
	elseif kind == "zap" then
		if e < 0.45 then
			local k = phase(e, 0, 0.45)
			local pulse = if math.floor(e * 16) % 2 == 0 then 1 else 0
			f.sq = Vector3.new(1 + 0.08 * pulse, 1 - 0.08 * pulse, 1 + 0.08 * pulse)
			f.dy = 0.25 * k
			f.tilt = CFrame.Angles(math.rad(-14) * k, 0, 0)
			f.action, f.mood, f.k = "cast", "attack", k * 0.5
		elseif e < 0.62 then
			local k = phase(e, 0.45, 0.62)
			f.du = dir * 0.6 * math.sin(k * math.pi)
			f.tilt = CFrame.Angles(math.rad(25) * math.sin(k * math.pi), 0, 0)
			f.dy = 0.25
			f.action, f.mood, f.k = "strike", "attack", k
		else
			f.dy = 0.25 * (1 - phase(e, 0.62, mv.dur))
		end
	elseif kind == "hurt" then
		local k = phase(e, 0, mv.dur)
		local out = if k < 0.18 then ease(k / 0.18) else 1 - ease((k - 0.18) / 0.82)
		f.du, f.dv = gu * 1.4 * out, gv * 1.4 * out
		f.tilt = CFrame.Angles(math.rad(-24) * out, 0, 0)
		f.sq = if k < 0.12 then Vector3.new(0.8, 1.2, 0.8) elseif k < 0.35 then Vector3.new(1.15, 0.85, 1.15) else SQ1
		f.action, f.mood = "hurt", "hurt"
	elseif kind == "ko" then
		local k = phase(e, 0, 0.55)
		f.du, f.dv = gu * 3.2 * ease(k), gv * 3.2 * ease(k)
		f.dy = math.sin(k * math.pi) * 2.2
		f.spin = k * math.pi * 2
		f.action, f.mood = if k < 1 then "hurt" else "ko", if k < 1 then "hurt" else "ko"
		if k >= 1 then
			local b = phase(e, 0.55, mv.dur)
			f.dy = math.sin(b * math.pi) * 0.5
			f.sq = Vector3.new(1.2 - 0.2 * b, 0.8 + 0.2 * b, 1.2 - 0.2 * b)
		end
	elseif kind == "guard" then
		local k = ease(phase(e, 0, 0.15))
		f.sq = Vector3.new(1 + 0.12 * k, 1 - 0.12 * k, 1 + 0.12 * k)
		f.tilt = CFrame.Angles(math.rad(8) * k, 0, 0)
		f.action, f.mood = "guard", "idle"
	elseif kind == "cast" then
		local k = phase(e, 0, mv.dur)
		f.dy = math.sin(k * math.pi) * 0.75
		f.spin = ease(k) * math.pi * 2
		f.action, f.mood = "cheer", "cheer"
	elseif kind == "throw" then
		f.action, f.k, f.mood = "throw", phase(e, 0, mv.dur), "cheer"
	elseif kind == "refuse" then
		f.spin = math.rad(28) * math.sin(e * 24) * (1 - phase(e, 0, mv.dur))
		f.action, f.mood = "stand", "hurt"
	elseif kind == "happy" then
		f.dy = math.abs(math.sin(e * 11)) * 0.9
		f.sq = if f.dy < 0.1 then Vector3.new(1.12, 0.88, 1.12) else Vector3.new(0.92, 1.08, 0.92)
		f.action, f.mood = "cheer", "cheer"
	elseif kind == "flee" or kind == "stumble" then
		local k = phase(e, 0, 0.5)
		f.spin = math.pi * ease(math.min(1, k * 3))
		f.du = -dir * 5 * easeIn(k)
		f.action, f.speed, f.mood = "run", 30, "walk"
		if kind == "stumble" and e >= 0.35 then
			-- trips over its feet and scrambles back
			local b = phase(e, 0.35, mv.dur)
			f.du = -dir * 5 * easeIn(phase(0.35, 0, 0.5)) * (1 - ease(b))
			f.tilt = CFrame.Angles(math.rad(70) * math.sin(math.min(1, b * 2) * math.pi / 2) * (1 - b), 0, 0)
			f.action, f.mood = if b < 0.5 then "hurt" else "run", "hurt"
		end
	elseif kind == "victory" then
		local hop = math.abs(math.sin(e * 9))
		f.dy = hop * 1.1
		f.sq = if hop < 0.15 then Vector3.new(1.15, 0.85, 1.15) else Vector3.new(0.9, 1.1, 0.9)
		f.spin = if e > 1.0 then ease(phase(e, 1.0, 1.4)) * math.pi * 2 else 0
		f.action, f.mood = "victory", "cheer"
	end
	return f
end


-- Every frame: everyone posed (idle bobs, lunges, drops, knock-outs), the stage's life.
local function poseAll(t: number, dt: number)
	local st = stage
	if st == nil then
		return
	end
	local now = os.clock()
	local frozen = now < freezeUntil
	-- the boat gliding in to the shore once the curtain is up
	local since = if lifted then now - opened - liftDelay else -1
	local sh = ship
	local shipU = shipU0
	if sh then
		local e = math.clamp(since / SHIP_IN, 0, 1)
		local ease = 1 - (1 - e) * (1 - e)
		shipU = SHIP_FROM + (shipU0 - SHIP_FROM) * ease
		local bob = if e >= 1 and math.floor(t * 1.5) % 2 == 0 then 0.125 else 0
		MicroModels.flutter(sh :: MicroModels.Thing, t)
		st.place(sh :: MicroModels.Thing, math.floor(shipU * 4 + 0.5) / 4, SHIP_V, WATER + bob, MicroStage.FACE_RIGHT)
	end
	for _, a in actors do
		-- the party hops off the arriving boat onto the shore one after another and runs to its places
		if a.deck > 0 then
			local spot = DECK_SPOTS[a.deck] or DECK_SPOTS[#DECK_SPOTS]
			local du, dv, dh = shipU + spot[1], SHIP_V + spot[2], WATER + deckH + spot[3]
			local k = since - (SHIP_IN + 0.1 + (a.deck - 1) * 0.35)
			local hu, hv = a.u, a.v
			local dx, dz = hu - du, hv - dv
			local dist = math.max(4, math.sqrt(dx * dx + dz * dz))
			local lu, lv = du + dx / dist * LAND, dv + dz / dist * LAND
			local u, v, y, action, speed = du, dv, dh, if since > 0 then "cheer" else "stand", 0
			if k >= HOP_T then
				local frac = math.min(1, (k - HOP_T) * RUN / (dist - LAND))
				u, v, y, action, speed = lu + (hu - lu) * frac, lv + (hv - lv) * frac, 0, "stand", RUN
				if frac >= 1 then
					a.deck = 0
					st.puff(st.at(hu, hv, 0.2), "dust", 4)
				end
			elseif k >= 0 then
				local e = k / HOP_T
				u, v = du + (lu - du) * e, dv + (lv - dv) * e
				y, action = dh * (1 - e) + math.sin(e * math.pi) * 1.8, "jump"
				if a.founder and k < dt then
					Audio.play("pop", { pitch = 0.75 })
					task.delay(HOP_T, function()
						Audio.play("splash")
					end)
				end
			end
			if a.deck > 0 then
				local dir = MicroStage.U_DIR * dx + MicroStage.V_DIR * dz
				local yaw = if k >= 0 then math.atan2(dir.X, dir.Z) else MicroStage.FACE_RIGHT
				if a.founder then
					st.pose(u, v, y, yaw, t, speed, action, 1)
				elseif a.rival then
					(a.rival :: MicroStage.Rival).pose(u, v, y, yaw, t, speed, action, 1)
				elseif a.thing then
					local hop = if speed > 0 and math.floor(t * 8 + a.ph) % 2 == 0 then 0.25 else 0
					st.place(a.thing :: MicroModels.Thing, u, v, y + hop, yaw)
				end
				continue
			end
		end
		-- drops land
		if a.dy > 0 and lifted and now >= a.enterAt and a.move == nil then
			a.dy = math.max(0, a.dy - dt * 30)
			if a.dy == 0 then
				st.puff(st.at(a.u, a.v, 0.2), "dust", 6)
			end
		end
		if now > a.until_ then
			a.action = "stand"
		end
		if a.gone then
			if a.thing then
				st.place(a.thing :: MicroModels.Thing, 0, 0, -50)
			end
			continue
		end
		-- a battle move: where it is, how it leans and squashes, what it does (frozen during a hit-stop)
		local fr: MoveFrame? = nil
		local mv = a.move
		if mv then
			if frozen then
				mv.t0 += dt
			end
			local e = now - mv.t0
			if e >= mv.dur then
				a.move = nil
				if mv.kind == "ko" then
					a.ko = true
				end
			else
				fr = frameOf(a, mv, e)
			end
		end
		local du, dv, dy = 0, 0, 0
		local tilt, sq, spin, action, k, mood, speed = CFrame.identity, Vector3.one, 0, a.action, 0, "idle", 0
		if fr then
			du, dv, dy, tilt, sq, spin, action, k, mood, speed = fr.du, fr.dv, fr.dy, fr.tilt, fr.sq, fr.spin, fr.action, fr.k, fr.mood, fr.speed
		elseif a.action == "cheer" then
			mood = "cheer"
		end
		a.du, a.dv = du, dv
		if fr == nil then
			dy = a.dy
		end
		local u = a.u + math.floor(du * 4 + 0.5) / 4
		local v = a.v + math.floor(dv * 4 + 0.5) / 4
		local y = math.floor(dy * 4 + 0.5) / 4
		local yaw = a.yaw + spin
		local entry = if lifted then a.dy else 8
		-- the founder and the villagers: knocked out they lie flat
		if a.founder or a.rival then
			local act0 = if a.ko and fr == nil then "ko" else action
			if a.founder then
				st.pose(u, v, y, yaw, t, speed, act0, k)
			else
				(a.rival :: MicroStage.Rival).pose(u, v, y, yaw, t, speed, act0, k)
			end
		elseif a.thing then
			local th = a.thing :: MicroModels.Thing
			-- squash and stretch in whole eighths
			local s0 = a.scale0
			local sx, sy = math.floor(sq.X * 8 + 0.5) / 8, math.floor(sq.Y * 8 + 0.5) / 8
			local key = sx .. ":" .. sy
			if key ~= a.sqKey then
				a.sqKey = key
				MicroModels.scale(th, Vector3.new(s0 * sx, s0 * sy, s0 * sx))
			end
			if a.ko and fr == nil then
				MicroModels.animate(th, t + a.ph, "ko", 0)
				st.place(th, u, v, 0, yaw, CFrame.Angles(0, 0, math.rad(90)))
			else
				MicroModels.animate(th, t + a.ph, mood, k)
				-- an idle hop in whole quarter studs; a happy bounce while cheering
				local hop = 0
				if fr == nil then
					hop = if a.action == "cheer" then (if math.floor(t * 8 + a.ph) % 2 == 0 then 0.75 else 0) else (if math.floor(t * 2.5 + a.ph) % 2 == 0 then 0.125 else 0)
				end
				st.place(th, u, v, (if fr then y else entry) + hop, yaw, tilt)
			end
		end
	end
	-- the picture's shake (whole art px)
	if now < shakeUntil then
		local m = math.max(1, math.floor(shakeAmp))
		PixelRenderer.setOffset(math.random(-m, m), math.random(-m, m))
		shaking = true
	elseif shaking then
		shaking = false
		PixelRenderer.setOffset(0, 0)
	end
	st.step(t, dt)
end

------------------------------------------------------------------ the overlay
local function canvasSize(): (number, number)
	local s = UIKit.size("Stage")
	return s.X, s.Y
end

-- The Stage root covers the whole screen: Roblox's top bar (its buttons) takes this many UI px at the top.
local function topInset(): number
	return math.ceil(UIKit.canvasOrigin("Hud").Y / math.max(1, UIKit.P()))
end

-- A word floating up over someone on the stage.
local function floatOver(key: string, text: string, color: Color3)
	local a = actors[key]
	local st, r = stage, root
	if a == nil or st == nil or r == nil then
		return
	end
	local x, y, on = st.screen(actorAt(a) + Vector3.new(0, headOf(a) + 1.2, 0))
	if on then
		UIKit.popText(r, x, y, text, color)
	end
end

-- The narration: a plate across the middle of the screen for a moment.
local sayFrame: Frame? = nil
local function say(text: string, color: Color3?, seconds: number?)
	local r = root
	if r == nil then
		return
	end
	if sayFrame then
		sayFrame:Destroy()
	end
	local w, _ = canvasSize()
	local tw = math.min(UIKit.textWidth(text) + 16, w - 16)
	local f = UIKit.plate(r, UDim2.fromOffset(tw, 14), UDim2.fromOffset(math.floor((w - tw) / 2), topInset() + HEAD_H + 2), UIKit.color("plate"), 0.05, 2)
	f.Name = "Say"
	f.ZIndex = 12
	UIKit.text(f, text, UDim2.fromScale(1, 1), nil, { x = "center", color = color or UIKit.color("text"), z = 13, name = "Words" })
	sayFrame = f
	task.delay(seconds or 1.8, function()
		if f.Parent and sayFrame == f then
			f:Destroy()
			sayFrame = nil
		end
	end)
end

local function setBar(key: string, hp: number)
	local b = bars[key]
	if b == nil then
		return
	end
	b.hp = math.clamp(hp, 0, b.maxHp)
	shownHp[key] = b.hp
	local fill, label = b.fill, b.label
	if fill then
		local k = b.hp / math.max(1, b.maxHp)
		fill.Size = UDim2.fromOffset(math.floor((b.w - 2) * k + 0.5), 2)
		fill.BackgroundColor3 = if k > 0.5 then UIKit.color("good") elseif k > 0.25 then UIKit.color("accent") else UIKit.color("bad")
	end
	if label then
		UIKit.setText(label, string.format("%d/%d", math.floor(b.hp + 0.5), b.maxHp))
	end
end

------------------------------------------------------------------ the timed battle
-- A fighter of the expedition (the view's: its speed sets its timer's pace), the party's or a wild one's.
local function fighterOf(key: string): Types.Fighter?
	local e = exp()
	if e == nil then
		return nil
	end
	for _, f in e.party do
		if f.key == key then
			return f
		end
	end
	local b = e.battle
	if b then
		for _, f in b.foes do
			if f.key == key then
				return f
			end
		end
	end
	return nil
end

-- The health shown for a fighter (the battle's events move it; the view's between battles).
local function hpOf(f: Types.Fighter): number
	local h = shownHp[f.key]
	return if h ~= nil then h else f.hp
end

-- A timer as it stands now (0 .. 1), run on from the server's last word (they fill while an action plays too).
local function gaugeOf(key: string): number
	local g0 = gaugeG[key] or 0
	local f = fighterOf(key)
	if gaugePaused or f == nil then
		return g0
	end
	local t = os.clock() - gaugeAt
	return math.min(1, g0 + t / (Battle.fillTime(f :: Types.Fighter) * gaugeCrowd))
end

-- The party's skill points now.
local function spOf(): number
	if gaugePaused then
		return spNow
	end
	return math.min(Tuning.SpMax, spNow + (os.clock() - gaugeAt) * Tuning.SpRate)
end

-- The server's word on the timers (an action's message, a sync, a pause's answer).
local function takeGauges(d: any)
	if type(d) ~= "table" then
		return
	end
	if type(d.g) == "table" then
		for k, v in d.g do
			if type(k) == "string" and type(v) == "number" then
				gaugeG[k] = v
			end
		end
	end
	gaugeLock = tonumber(d.lock) or 0
	if type(d.crowd) == "number" and d.crowd >= 1 and d.crowd < 100 then
		gaugeCrowd = d.crowd
	end
	if type(d.paused) == "boolean" then
		gaugePaused = d.paused
	end
	if type(d.sp) == "number" then
		spNow = d.sp
	end
	if type(d.snacks) == "number" then
		snacksLeft = d.snacks
	end
	gaugeAt = os.clock()
end

-- Pause the battle or let it run (the server's answer brings the timers as they stand).
local function setPaused(on: boolean)
	-- (the timers stop where they are shown at once)
	if on and not gaugePaused then
		for k in gaugeG do
			gaugeG[k] = gaugeOf(k)
		end
		spNow = spOf()
	end
	gaugePaused = on
	gaugeAt = os.clock()
	gaugeLock = 0
	task.spawn(function()
		local res = StateClient.request("exp.pause", { on = on })
		if res.ok then
			takeGauges(res.data)
		end
	end)
end

-- The wild ones still in the battle (not beaten, not befriended) and the party's members, standing or down.
local function foesLeft(): { Types.Fighter }
	local out: { Types.Fighter } = {}
	local e = exp()
	local b = if e then e.battle else nil
	if b then
		for _, f in b.foes do
			local a = actors[f.key]
			if hpOf(f) > 0 and not (a and a.gone) then
				table.insert(out, f)
			end
		end
	end
	return out
end
local function partyList(down: boolean): { Types.Fighter }
	local out: { Types.Fighter } = {}
	local e = exp()
	if e then
		for _, f in e.party do
			if (hpOf(f) <= 0) == down then
				table.insert(out, f)
			end
		end
	end
	return out
end

-- What an aim can pick, in order (the side's members left to right).
local function candidates(side: string): { Types.Fighter }
	if side == "foe" then
		return foesLeft()
	elseif side == "ally" then
		return partyList(false)
	elseif side == "down" then
		return partyList(true)
	end
	return {}
end

-- A first pick: the most hurt (a foe for a snack or a blow, a member for a mend), the first one down for a revive.
local function firstPick(side: string): string?
	local best: Types.Fighter? = nil
	for _, f in candidates(side) do
		if best == nil or hpOf(f) / math.max(1, f.maxHp) < hpOf(best :: Types.Fighter) / math.max(1, (best :: Types.Fighter).maxHp) then
			best = f
		end
	end
	return if best then best.key else nil
end

-- The aim on the floor (every frame): the ring round the one acting, a dashed arrow from it all the way to the pick
-- (the dashes marching toward it), a ring under the pick, and the pointer over its head. The arrow's end glides to a
-- new pick (so the arrow swings and stretches over), grows out of the ring when the aim opens, and the pick's ring
-- pops in.
local AIM_DASH, AIM_GAP = 0.5, 0.75 -- a dash's length and the dashes' spacing (studs)
local function dropAim(st: MicroStage.Stage?)
	for _, t in { aimMark, aimPath, aimRing } do
		if t and st then
			st.remove(t)
		end
	end
	aimMark, aimPath, aimRing, aimEndU, aimRingFor = nil, nil, nil, nil, nil
	if aimPointer then
		(aimPointer :: GuiObject):Destroy()
		aimPointer = nil
	end
end

-- Show or hide every part of a floor thing (the renderer skips a see-through part).
local function showThing(t: MicroModels.Thing, on: boolean)
	for _, p in t.parts do
		p.Transparency = if on then 0 else 1
	end
end

local function updateAim()
	local st, a, r = stage, aim, root
	if st == nil or r == nil or a == nil then
		dropAim(st)
		return
	end
	local user = actors[a.who]
	if user == nil then
		return
	end
	local now = os.clock()
	local dt = math.clamp(now - aimClock, 0, 0.1)
	aimClock = now
	if aimMark == nil then
		local color = if a.kind == "snack" then "pink" else "yellow"
		aimMark = st.spawn("aim", { color = color })
		aimPath = st.spawn("aimpath", { color = color })
		aimRing = st.spawn("aimring", { color = color })
		aimEndU, aimRingFor = nil, nil
	end
	local mark, path, ring = aimMark :: MicroModels.Thing, aimPath :: MicroModels.Thing, aimRing :: MicroModels.Thing
	local u0, v0 = user.u + user.du, user.v + user.dv
	-- the leader's ring turns slowly
	st.place(mark, u0, v0, 0.05, now * 0.5)
	-- (the pick may be the user itself, a mend on the leader: its ring sits inside the user's, no arrow)
	local tgt = if a.target then actors[a.target :: string] else nil
	if tgt == nil then
		showThing(path, false)
		showThing(ring, false)
		aimEndU = nil
		if aimPointer then
			(aimPointer :: GuiObject):Destroy()
			aimPointer = nil
		end
		return
	end
	local pick = tgt :: Actor
	-- the end glides to the pick (out of the leader's ring when the aim opens)
	local u1, v1 = pick.u + pick.du, pick.v + pick.dv
	if aimEndU == nil then
		aimEndU, aimEndV, aimRingR = u0, v0, 0
	end
	local k = 1 - math.exp(-dt * 12)
	local eu = (aimEndU :: number) + (u1 - (aimEndU :: number)) * k
	local ev = aimEndV + (v1 - aimEndV) * k
	aimEndU, aimEndV = eu, ev
	if aimRingFor ~= a.target then
		aimRingFor = a.target
		aimRingR *= 0.4
	end
	local want = if pick.big then 2.1 else 1.3
	aimRingR += (want - aimRingR) * (1 - math.exp(-dt * 14))
	-- the arrow: from the leader's ring's edge to the pick's ring's edge
	local p0, p1 = st.at(u0, v0, 0), st.at(eu, ev, 0)
	local dx, dz = p1.X - p0.X, p1.Z - p0.Z
	local dist = math.sqrt(dx * dx + dz * dz)
	local s0, s1 = 2.1, dist - aimRingR - 0.3
	local on = s1 > s0 + 0.5
	local phase = (now * 1.5) % AIM_GAP
	for i = 1, MicroModels.AIM_DASHES do
		local name = "D" .. i
		local z = s0 + phase + (i - 1) * AIM_GAP
		local shown = on and z - AIM_DASH / 2 >= s0 - 0.01 and z + AIM_DASH / 2 <= s1 - 0.5
		local part = path.parts[name]
		if part then
			part.Transparency = if shown then 0 else 1
		end
		path.rest[name] = CFrame.new(0, 0.07, if shown then z else 0)
	end
	for _, side in { -1, 1 } do
		local name = if side < 0 then "HeadL" else "HeadR"
		local part = path.parts[name]
		if part then
			part.Transparency = if on then 0 else 1
		end
		path.rest[name] = CFrame.new(0.28 * side, 0.07, s1 - 0.34) * CFrame.Angles(0, math.rad(-40 * side), 0)
	end
	st.place(path, u0, v0, 0.05, math.atan2(dx, dz))
	-- the pick's ring, turning the other way
	showThing(ring, true)
	for i = 1, MicroModels.AIM_RING do
		local ang = (i - 0.5) / MicroModels.AIM_RING * math.pi * 2 - now * 0.8
		ring.rest["R" .. i] = CFrame.new(math.cos(ang) * aimRingR, 0.07, math.sin(ang) * aimRingR) * CFrame.Angles(0, -ang + math.pi / 2, 0)
	end
	st.place(ring, eu, ev, 0.05, 0)
	-- the pointer: a small arrow bobbing over the pick's head (gliding with the arrow's end)
	if aimPointer == nil then
		local img = PixelSprites.image(r, "arrow_down_t", UDim2.fromOffset(0, 0), 24)
		img.Name = "AimPointer"
		aimPointer = img
	end
	local x, y, vis = st.screen(st.at(eu, ev, pick.dy) + Vector3.new(0, headOf(pick) + 1.3, 0))
	local bob = math.floor(math.sin(now * 6) * 1.5 + 0.5)
	local ap = aimPointer :: GuiObject
	ap.Visible = vis
	ap.Position = UDim2.fromOffset(math.floor(x) - 3, math.floor(y) - 9 + bob)
end

-- The timers over everyone's heads (every frame in a battle): a small bar each, gold for the party, orange for the
-- wild ones; full (ready, waiting for the action playing to end) it flashes white.
local function updateTimers()
	local r, st = root, stage
	local e = exp()
	local folder = if r then r:FindFirstChild("Timers") else nil
	local show = e ~= nil and e.battle ~= nil and lifted and st ~= nil and folder ~= nil
	for key, tb in timerBars do
		local a = actors[key]
		local f = fighterOf(key)
		if not show or a == nil or a.gone or a.ko or f == nil or hpOf(f :: Types.Fighter) <= 0 then
			tb.frame:Destroy()
			timerBars[key] = nil
		end
	end
	if not show then
		return
	end
	for key, a in actors do
		local f = fighterOf(key)
		if f == nil or a.gone or a.ko or hpOf(f :: Types.Fighter) <= 0 or a.deck > 0 then
			continue
		end
		local tb = timerBars[key]
		if tb == nil then
			local w = if a.big then 22 else 16
			local frame = UIKit.rect(folder :: Instance, UDim2.fromOffset(w, 4), UDim2.fromOffset(0, 0), UIKit.color("ink"), 20)
			frame.Name = "Timer_" .. key
			local fill = UIKit.rect(frame, UDim2.fromOffset(0, 2), UDim2.fromOffset(1, 1), UIKit.color("accent"), 21)
			fill.Name = "Fill"
			tb = { frame = frame, fill = fill, w = w }
			timerBars[key] = tb
		end
		local bar = tb :: { frame: Frame, fill: Frame, w: number }
		local x, y, on = (st :: MicroStage.Stage).screen(actorAt(a) + Vector3.new(0, headOf(a) + 0.6, 0))
		bar.frame.Visible = on
		bar.frame.Position = UDim2.fromOffset(math.floor(x) - math.floor(bar.w / 2), math.floor(y) - 2)
		local g = gaugeOf(key)
		bar.fill.Size = UDim2.fromOffset(math.floor((bar.w - 2) * g), 2)
		local side = if a.foe then UIKit.color("orange") else UIKit.color("accent")
		bar.fill.BackgroundColor3 = if g >= 1 and math.floor(os.clock() * 4) % 2 == 0 then UIKit.color("text") else side
	end
end

-- A fighter's card: its portrait or icon, name and level, its health bar (a tap picks it while aiming).
local function fighterCard(parent: Instance, f: Types.Fighter, x: number, y: number, w: number, foe: boolean): Frame
	local selected = aim ~= nil and (aim :: Aim).target == f.key
	local card = UIKit.plate(parent, UDim2.fromOffset(w, 18), UDim2.fromOffset(x, y), if selected then UIKit.color("accent") else UIKit.color("plate_light"), 0.03, 2, { bevel = true })
	card.Name = "Card_" .. f.key
	card.ZIndex = 10
	if f.sp then
		local icon = PixelSprites.image(card, "icon_" .. (f.sp :: string), UDim2.fromOffset(1, 1), 11)
		local _ = icon
	elseif f.look then
		UIKit.portrait(card, f.look :: Types.Look, 16, UDim2.fromOffset(1, 1)).ZIndex = 11
	end
	UIKit.text(card, f.name, UDim2.fromOffset(w - 20, 9), UDim2.fromOffset(19, 0), { color = if selected then UIKit.color("ink") else UIKit.color("text"), kind = if selected then "plain" else nil, z = 11, name = "Name" })
	-- the level beside the health bar (a long name keeps the whole top line)
	local lv = "Lv" .. f.lvl
	local lvW = UIKit.textWidth(lv)
	UIKit.text(card, lv, UDim2.fromOffset(lvW + 2, 9), UDim2.fromOffset(w - lvW - 3, 8), { x = "right", color = if selected then UIKit.color("ink") else UIKit.color("text_dim"), kind = if selected then "plain" else nil, z = 11, name = "Lv" })
	local bw = w - 21 - lvW - 3
	local back = UIKit.rect(card, UDim2.fromOffset(bw, 4), UDim2.fromOffset(19, 10), UIKit.color("ink"), 11)
	back.Name = "HpBack"
	local fill = UIKit.rect(back, UDim2.fromOffset(bw - 2, 2), UDim2.fromOffset(1, 1), UIKit.color("good"), 12)
	fill.Name = "HpFill"
	local label = UIKit.text(card, "", UDim2.fromOffset(bw, 8), UDim2.fromOffset(19, 11), { x = "right", color = UIKit.color("text_dim"), z = 13, name = "Hp" })
	label.Visible = false
	bars[f.key] = { hp = hpOf(f), maxHp = f.maxHp, name = f.name, lvl = f.lvl, card = card, fill = fill, label = label, w = bw }
	setBar(f.key, hpOf(f))
	local _ = foe
	local pick = Instance.new("TextButton")
	pick.Name = "Pick"
	pick.Text = ""
	pick.BackgroundTransparency = 1
	pick.Size = UDim2.fromScale(1, 1)
	pick.ZIndex = 14
	pick.Parent = card
	pick.Activated:Connect(function()
		pickTarget(f.key)
	end)
	return card
end

local function lootLine(parent: Instance, e: Types.Expedition, x: number, y: number)
	local items: { { icon: string, n: number } } = { { icon = "shell", n = e.loot.shells }, { icon = "food", n = e.loot.food }, { icon = "wood", n = e.loot.wood } }
	for _, it in items do
		PixelSprites.image(parent, "mini_" .. it.icon, UDim2.fromOffset(x, y), 11)
		local t = Numbers.coins(it.n)
		UIKit.text(parent, t, UDim2.fromOffset(UIKit.textWidth(t) + 2, 10), UDim2.fromOffset(x + 12, y + 1), { color = UIKit.color("text"), z = 11, name = "Loot_" .. it.icon })
		x += 16 + UIKit.textWidth(t)
	end
end

------------------------------------------------------------------ requests
local function ask(action: string, payload: { [string]: any }?): Types.Response
	local res = StateClient.request(action, payload)
	if not res.ok then
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
	end
	return res
end

local playRound: (data: { [string]: any }) -> ()
local playNode: (data: { [string]: any }) -> ()
local goHome: () -> ()

local function goOn()
	if busy then
		return
	end
	busy = true
	refresh()
	-- the party walks on: a few steps in place while the next stop comes up
	for _, a in actors do
		if not a.foe and not a.ko then
			act(a, "stand", 0.6)
		end
	end
	Audio.play("tick")
	local res = ask("exp.next", {})
	if res.ok and type(res.data) == "table" then
		playNode(res.data :: { [string]: any })
	end
	busy = false
	refresh()
end

-- Aiming and choosing pause the battle and grey the picture; back to the battle: it runs again, in colour.
local function holdBattle(on: boolean)
	DayLight.hold(if on then GREY else nil)
	setPaused(on)
end

-- Stop aiming (and choosing a skill); `resume`: the battle runs again (not when an action was sent: it runs then).
local function endAim(resume: boolean)
	local was = aim ~= nil or skillMenu
	aim = nil
	skillMenu = false
	updateAim()
	if was then
		DayLight.hold(nil)
		if resume then
			setPaused(false)
		end
	end
	refresh()
end

-- A snack: aim at a wild one (the leader's ring and arrow), then throw.
local function startSnack()
	local e = exp()
	local b = if e then e.battle else nil
	if b == nil or busy or aim then
		return
	end
	if b.boss then
		UIKit.notice("The guardian won't take a snack.", UIKit.color("bad"))
		Audio.play("deny")
		return
	end
	if snacksLeft <= 0 then
		UIKit.notice(Words.errText("no_snacks"), UIKit.color("bad"))
		Audio.play("deny")
		return
	end
	local lead = actors.f
	if lead == nil or lead.ko then
		UIKit.notice("The leader is down: no snacks till they're up.", UIKit.color("bad"))
		Audio.play("deny")
		return
	end
	skillMenu = false
	aim = { kind = "snack", who = "f", skill = nil, side = "foe", target = firstPick("foe") }
	holdBattle(true)
	Audio.play("open")
	refresh()
end

-- The skill window (it pauses and greys the battle like a snack).
local function openSkills()
	local e = exp()
	if e == nil or e.battle == nil or busy then
		return
	end
	if aim then
		aim = nil
		updateAim()
	else
		holdBattle(true)
	end
	skillMenu = true
	Audio.play("open")
	refresh()
end

-- Pick a skill from the window: one aiming at nobody goes at once; one with a side to aim at opens the aim.
local useAim: () -> ()
local function chooseSkill(who: string, id: string)
	local d = Skills.byId[id]
	if d == nil then
		return
	end
	skillMenu = false
	aim = { kind = "skill", who = who, skill = id, side = d.target, target = if d.target == "none" then nil else firstPick(d.target) }
	if d.target == "none" then
		useAim()
	else
		Audio.play("flip")
		refresh()
	end
end

-- The pick moves on (keys) or lands on a fighter (a tap on its card or on the stage).
pickTarget = function(key: string?)
	local a = aim
	if a == nil or a.side == "none" then
		return
	end
	local list = candidates(a.side)
	if #list == 0 then
		return
	end
	if key then
		for _, f in list do
			if f.key == key then
				if a.target == key then
					-- a second tap on the pick: go
					task.spawn(useAim)
					return
				end
				a.target = key
				Audio.play("tick")
				refresh()
				return
			end
		end
		return
	end
	-- the next one along
	local i = 0
	for j, f in list do
		if f.key == a.target then
			i = j
		end
	end
	a.target = list[i % #list + 1].key
	Audio.play("tick")
	refresh()
end

-- Who on the stage is under a point (art px, as `stage.screen` gives them), among those the aim can pick: the
-- nearest whose figure (feet to head, a little wider than half as tall) holds it.
local function pickAt(i: number, j: number): string?
	local st, a = stage, aim
	if st == nil or a == nil then
		return nil
	end
	local best: string? = nil
	local bestD = math.huge
	for _, f in candidates((a :: Aim).side) do
		local ac = actors[f.key]
		if ac == nil or ac.gone or ac.deck > 0 then
			continue
		end
		local base = actorAt(ac)
		local fx, fy, on = (st :: MicroStage.Stage).screen(base)
		local _, hy = (st :: MicroStage.Stage).screen(base + Vector3.new(0, headOf(ac), 0))
		if not on then
			continue
		end
		local half = math.max(6, (fy - hy) * 0.35)
		if i >= fx - half and i <= fx + half and j >= hy - 4 and j <= fy + 4 then
			local d = math.abs(i - fx) + math.abs(j - (fy + hy) / 2) * 0.5
			if d < bestD then
				best, bestD = f.key, d
			end
		end
	end
	return best
end

-- The pointer over the stage while aiming: hovering (a mouse) picks whoever it is over; a tap or click on someone
-- picks them, and on the pick already chosen throws or uses it. Whether it was over someone.
local function pointAt(i: number, j: number, tap: boolean): boolean
	local a = aim
	if a == nil or busy or (a :: Aim).side == "none" then
		return false
	end
	local key = pickAt(i, j)
	if key == nil then
		return false
	end
	if tap then
		pickTarget(key)
	elseif key ~= (a :: Aim).target then
		(a :: Aim).target = key
		Audio.play("tick")
		refresh()
	end
	return true
end

-- Throw the snack or use the skill at the pick: the server does it, its events come as the battle's next message.
useAim = function()
	local a = aim
	if a == nil or busy then
		return
	end
	if a.side ~= "none" and a.target == nil then
		Audio.play("deny")
		return
	end
	busy = true
	local res: Types.Response
	if a.kind == "snack" then
		res = ask("exp.snack", { target = a.target or "" })
	else
		res = ask("exp.skill", { who = a.who, skill = a.skill or "", target = a.target or "" })
	end
	busy = false
	if res.ok then
		takeGauges(res.data)
		endAim(false)
	else
		endAim(true)
	end
end

-- Run (a chance; a miss starts the leader's timer again).
local function flee()
	local e = exp()
	if e == nil or e.battle == nil or busy or aim or skillMenu then
		return
	end
	busy = true
	local res = ask("exp.flee", {})
	busy = false
	if res.ok then
		takeGauges(res.data)
	end
	refresh()
end

-- The skill window: each standing member's skills learnt (their level), the cost in skill points; a skill the
-- points don't cover yet, or with nobody to aim at, greyed.
local function skillWindow(r: Frame, e: Types.Expedition)
	local w, h = canvasSize()
	local rows: { { f: Types.Fighter, list: { Skills.Skill } } } = {}
	for _, f in e.party do
		if hpOf(f) > 0 then
			local list = Skills.known(Skills.lineOf(f.kind, f.skill), f.lvl)
			if #list > 0 then
				table.insert(rows, { f = f, list = list })
			end
		end
	end
	-- the layout first: each member's skills flow along their row from the name column, onto further lines when they
	-- run out of room (none is ever dropped)
	local ww = math.min(w - 16, 340)
	local LINE = 17
	local placed: { { f: Types.Fighter, y: number, items: { { d: Skills.Skill, x: number, y: number, bw: number, label: string } } } } = {}
	local cy = 2
	for _, row in rows do
		local items = {}
		local x, y = 70, cy
		for _, d in row.list do
			local label = string.format("%s %d", d.name, d.cost)
			local bw = math.min(UIKit.buttonWidth(label, 4), ww - 78)
			if x + bw > ww - 8 and x > 70 then
				x, y = 70, y + LINE
			end
			table.insert(items, { d = d, x = x, y = y, bw = bw, label = label })
			x += bw + 3
		end
		table.insert(placed, { f = row.f, y = cy, items = items })
		cy = y + LINE + 5
	end
	local contentH = cy
	-- the window fits between the header and the footer (its frame too): it scrolls when the party's skills don't
	local top0 = topInset() + HEAD_H + 6
	local room = math.max(40, (h - FOOT_H - 6) - top0 - 8)
	local wh = math.min(20 + contentH, room)
	local wy = top0 + 4 + math.max(0, math.floor((room - wh) / 2))
	local win = UIKit.plate(r, UDim2.fromOffset(ww, wh), UDim2.fromOffset(math.floor((w - ww) / 2), wy), UIKit.color("plate"), 0, 3, { shadow = true, wood = 3 })
	win.Name = "SkillWindow"
	win.ZIndex = 26
	UIKit.plank(win, 15, 3)
	UIKit.text(win, "Skills", UDim2.fromOffset(80, 12), UDim2.fromOffset(6, 3), { color = UIKit.color("paper"), z = 28, name = "Title" })
	local sp = spOf()
	UIKit.text(win, string.format("Skill points %d/%d", math.floor(sp), Tuning.SpMax), UDim2.fromOffset(120, 12), UDim2.fromOffset(ww - 168, 3), { x = "right", color = UIKit.color("accent"), z = 28, name = "SpText" })
	local close = UIKit.button(win, "Back", UDim2.fromOffset(40, 12), UDim2.fromOffset(ww - 44, 3), function()
		endAim(true)
	end, { name = "Skills_close", color = UIKit.color("button_close") })
	close.ZIndex = 28
	local holder: GuiObject
	if 20 + contentH > room then
		local sc = UIKit.scroll(win, UDim2.fromOffset(ww - 4, wh - 19), UDim2.fromOffset(2, 17))
		sc.AutomaticCanvasSize = Enum.AutomaticSize.None
		sc.CanvasSize = UDim2.fromOffset(0, contentH)
		sc.ZIndex = 27
		holder = sc
	else
		local fr = Instance.new("Frame")
		fr.BackgroundTransparency = 1
		fr.BorderSizePixel = 0
		fr.Size = UDim2.fromOffset(ww - 4, contentH)
		fr.Position = UDim2.fromOffset(2, 17)
		fr.ZIndex = 27
		fr.Parent = win
		holder = fr
	end
	holder.Name = "SkillRows"
	for _, row in placed do
		local f, y = row.f, row.y
		if f.sp then
			PixelSprites.image(holder, "icon_" .. (f.sp :: string), UDim2.fromOffset(3, y + 1), 28)
		elseif f.look then
			UIKit.portrait(holder, f.look :: Types.Look, 16, UDim2.fromOffset(3, y + 1)).ZIndex = 28
		end
		UIKit.text(holder, f.name, UDim2.fromOffset(46, 10), UDim2.fromOffset(21, y + 4), { color = UIKit.color("text"), z = 28, name = "Who_" .. f.key })
		for _, it in row.items do
			local d = it.d
			local ok = sp + 1e-6 >= d.cost and (d.target == "none" or #candidates(d.target) > 0)
			local b = UIKit.button(holder, it.label, UDim2.fromOffset(it.bw, 15), UDim2.fromOffset(it.x - 2, it.y), function()
				chooseSkill(f.key, d.id)
			end, { name = "Skill_" .. f.key .. "_" .. d.id, color = if ok then UIKit.color("accent") else nil, enabled = ok })
			b.ZIndex = 28
		end
	end
end

------------------------------------------------------------------ playback
local function nameOf(key: string): string
	local b = bars[key]
	return if b then b.name else key
end

local function flashActor(a: Actor)
	local st = stage
	if st and a.thing then
		st.flash(a.thing :: MicroModels.Thing, 0.12)
	end
end

local playingSkill = false -- the events playing are a learnt skill's (named once, by its "skill" event)
local function playEvent(ev: { [string]: any })
	local st = stage
	if st == nil then
		return
	end
	local t = ev.t
	if t == "hit" then
		local by, to = actors[ev.by], actors[ev.to]
		local skill = ev.skill
		local kind = Battle.moveOf(skill)
		if skill and Skills.byId[skill] == nil then
			-- an auto skill names itself (a learnt one was named by its "skill" event)
			floatOver(ev.by, (Creatures.skills[skill] or skill) .. "!", UIKit.color("accent"))
			Audio.play("combo")
		end
		local t0 = os.clock()
		local impacts = IMPACTS[kind]
		if by then
			startMove(by, kind, to)
			task.delay(if kind == "quick" then 0.08 elseif kind == "bash" then 0.3 elseif kind == "zap" then 0 else 0.2, function()
				if kind ~= "zap" then
					Audio.play(if kind == "bash" then "whoosh_heavy" else "whoosh")
				end
			end)
		else
			impacts = { 0.05 }
		end
		local function at(seconds: number)
			local w = t0 + seconds - os.clock()
			if w > 0 then
				task.wait(w)
			end
		end
		-- the run-up's dust and the skills' own effects
		if by and kind ~= "zap" then
			at(if kind == "quick" then 0.08 else 0.2)
			st.puff(actorAt(by) + Vector3.new(0, 0.2, 0), "dust", if kind == "bash" then 10 else 5)
			if kind == "quick" then
				-- afterimages along the dash
				for j = 1, 3 do
					task.delay(j * 0.03, function()
						if by.thing or by.founder or by.rival then
							st.puff(actorAt(by) + Vector3.new(0, 1, 0), "twinkle", 2)
						end
					end)
				end
			end
		elseif by and kind == "zap" then
			-- charging up: sparks gather round it, then a bolt runs to the target
			for j = 1, 3 do
				at(0.1 * j)
				st.puff(actorAt(by) + Vector3.new(0, 1.2, 0), "spark", 4)
				if by.thing then
					st.flash(by.thing :: MicroModels.Thing, 0.05)
				end
			end
			at(0.45)
			Audio.play("zap")
			if to then
				local p0, p1 = actorAt(by) + Vector3.new(0, 1.2, 0), actorAt(to) + Vector3.new(0, 1.2, 0)
				for j = 0, 6 do
					st.puff(p0:Lerp(p1, j / 6) + Vector3.new(0, (j % 2) * 0.5 - 0.25, 0), "spark", 2)
				end
			end
		end
		local dmg = tonumber(ev.dmg) or 0
		for i, when in impacts do
			at(when)
			if to then
				local last = i == #impacts
				flashActor(to)
				st.puff(actorAt(to) + Vector3.new(0, 1.4, 0), if kind == "zap" then "splash" else "spark", if kind == "bash" then 12 else 7)
				if kind == "bash" then
					st.puff(actorAt(to) + Vector3.new(0, 0.2, 0), "dust", 14)
					st.puff(actorAt(to) + Vector3.new(0, 0.4, 0), "debris", 8)
				end
				if last then
					startMove(to, if ev.ko then "ko" else "hurt", by)
				end
				shake(if kind == "bash" or ev.ko then 2 else 1, if kind == "bash" then 0.25 else 0.14)
				freeze(if kind == "quick" then 0.035 else 0.07)
				t0 += if kind == "quick" then 0.035 else 0.07
			end
			local heavy = kind == "bash" or (ev.ko and i == #impacts)
			Audio.play(if heavy then "hit_heavy" else "hit")
			if by and by.thing and kind == "attack" then
				Audio.play("bite")
			end
		end
		local b = bars[ev.to]
		if b then
			setBar(ev.to, b.hp - dmg)
		end
		floatOver(ev.to, "-" .. tostring(dmg), UIKit.color("bad"))
		if ev.ko and to then
			floatOver(ev.to, "Down!", UIKit.color("text_dim"))
			Audio.play("pop", { pitch = 0.7 })
			task.delay(0.55, function()
				if isOpen and stage then
					Audio.play("body_fall")
					st.puff(actorAt(to), "dust", 10)
					st.puff(actorAt(to) + Vector3.new(0, 1.2, 0), "twinkle", 4)
				end
			end)
		end
		at(MOVES[kind] - 0.15)
	elseif t == "heal" then
		local by, to = actors[ev.by], actors[ev.to]
		if not playingSkill then
			floatOver(ev.by, "Soothe!", UIKit.color("good"))
		end
		if by then
			startMove(by, "cast")
			st.puff(actorAt(by) + Vector3.new(0, 1.2, 0), "twinkle", 4)
		end
		task.wait(0.3)
		if to then
			st.puff(actorAt(to) + Vector3.new(0, 1, 0), "heal", 10)
			if to ~= by then
				startMove(to, "happy")
			end
		end
		local b = bars[ev.to]
		if b then
			setBar(ev.to, b.hp + (tonumber(ev.amt) or 0))
		end
		floatOver(ev.to, "+" .. tostring(ev.amt), UIKit.color("good"))
		Audio.play("heal")
	elseif t == "shield" then
		local by = actors[ev.by]
		if not playingSkill then
			floatOver(ev.by, "Shell Guard!", UIKit.color("accent"))
		end
		if by then
			startMove(by, "cast")
		end
		task.wait(0.25)
		for _, a in actors do
			if by and a.foe == by.foe and not a.ko then
				if a ~= by then
					startMove(a, "guard")
				end
				st.puff(actorAt(a) + Vector3.new(if a.foe then -1 else 1, 1.2, 0), "twinkle", 4)
			end
		end
		Audio.play("shield")
	elseif t == "rally" then
		local by = actors[ev.by]
		if by then
			startMove(by, "cast")
		end
		if not playingSkill then
			floatOver(ev.by, "Rally!", UIKit.color("accent"))
		end
		for _, a in actors do
			if by and a.foe == by.foe and not a.ko and a ~= by then
				startMove(a, "happy")
			end
		end
		Audio.play("poof")
		Audio.play("cheer")
	elseif t == "skill" then
		-- a learnt skill: its name over the one using it, a flourish
		local by = actors[ev.by]
		local d = Skills.byId[ev.id]
		floatOver(ev.by, (if d then d.name else "Skill") .. "!", UIKit.color("accent"))
		if by then
			startMove(by, "cast")
			st.puff(actorAt(by) + Vector3.new(0, 1.4, 0), "spark", 6)
		end
		Audio.play("combo")
	elseif t == "revive" then
		local by, to = actors[ev.by], actors[ev.to]
		if by then
			startMove(by, "cast")
		end
		task.wait(0.3)
		if to then
			to.ko = false
			startMove(to, "happy")
			st.puff(actorAt(to) + Vector3.new(0, 1, 0), "heal", 12)
			st.puff(actorAt(to) + Vector3.new(0, 1.6, 0), "twinkle", 6)
		end
		setBar(ev.to, tonumber(ev.amt) or 1)
		floatOver(ev.to, "Back up!", UIKit.color("good"))
		Audio.play("heal", { pitch = 1.2 })
	elseif t == "haste" then
		for _, a in actors do
			if not a.foe and not a.ko then
				startMove(a, "happy")
				st.puff(actorAt(a) + Vector3.new(0, 0.3, 0), "dust", 5)
			end
		end
		say("The party springs into action!", UIKit.color("accent"), 1.2)
		Audio.play("whoosh", { pitch = 1.3 })
	elseif t == "dizzy" then
		for _, a in actors do
			if a.foe and not a.ko then
				startMove(a, "stumble")
				st.puff(actorAt(a) + Vector3.new(0, 2, 0), "twinkle", 4)
			end
		end
		say("The wild ones are dizzy!", UIKit.color("accent"), 1.2)
		Audio.play("poof")
	elseif t == "treat" then
		local to = actors[ev.to]
		local f = actors.f
		if f then
			startMove(f, "throw")
		end
		floatOver("f", "Here, a snack!", UIKit.color("text"))
		Audio.play("whoosh", { pitch = 1.3 })
		task.wait(0.3)
		if f and to then
			-- the treat's arc: a trail of sparkles from the founder's hand to the wild one
			local p0, p1 = actorAt(f) + Vector3.new(0, 2.5, 0), actorAt(to) + Vector3.new(0, 1.5, 0)
			for j = 1, 5 do
				local q = j / 5
				st.puff(p0:Lerp(p1, q) + Vector3.new(0, math.sin(q * math.pi) * 2.5, 0), "twinkle", 1)
				task.wait(0.04)
			end
		end
		if to then
			if ev.ok then
				st.puff(actorAt(to) + Vector3.new(0, 1.5, 0), "heart", 12)
				startMove(to, "happy")
				floatOver(ev.to, "<3", UIKit.color("pink"))
				Audio.play("fanfare")
				say(nameOf(ev.to) .. " wants to be friends!", UIKit.color("pink"), 2)
				task.wait(0.7)
				to.gone = true
				st.puff(actorAt(to), "confetti")
				local b = bars[ev.to]
				if b and b.card then
					(b.card :: Frame).Visible = false
				end
			else
				startMove(to, "refuse")
				st.puff(actorAt(to) + Vector3.new(0, 1.2, 0), "dust", 3)
				floatOver(ev.to, "Hmph!", UIKit.color("text_dim"))
				Audio.play("deny")
			end
		end
	elseif t == "flee" then
		for _, a in actors do
			if not a.foe and not a.ko then
				startMove(a, if ev.ok then "flee" else "stumble")
				st.puff(actorAt(a) + Vector3.new(0, 0.2, 0), "dust", 4)
			end
		end
		Audio.play("whoosh", { pitch = 0.8 })
		if ev.ok then
			say("Got away!", UIKit.color("good"), 1.4)
			Audio.play("pop")
		else
			say("Couldn't get away!", UIKit.color("bad"), 1.4)
			Audio.play("deny")
		end
	end
	task.wait(if t == "hit" then 0.15 else STEP)
end

-- A won battle's small alert (GAME_DESIGN 7: "the onward popup should just be a small alert"): a plate under the
-- header with the title, its lines and maybe a new friend's portrait; it slides down, stays AUTO_CARD seconds and
-- goes by itself (no button: the party walks on meanwhile).
local alertFrame: Frame? = nil
local function alert(title: string, color: Color3, lines: { { text: string, color: Color3? } }, icon: string?)
	local r = root
	if r == nil then
		return
	end
	if alertFrame then
		alertFrame:Destroy()
	end
	local w, _ = canvasSize()
	local tw = UIKit.textWidth(title) + 8
	for _, l in lines do
		tw = math.max(tw, UIKit.textWidth(l.text) + 8)
	end
	local ix = if icon then 20 else 0
	local cw = math.min(w - 16, tw + ix + 8)
	local ch = 4 + 10 + #lines * 9 + 3
	if icon then
		ch = math.max(ch, 22)
	end
	local x, y = math.floor((w - cw) / 2), topInset() + HEAD_H + 18
	local f = UIKit.plate(r, UDim2.fromOffset(cw, ch), UDim2.fromOffset(x, y - 6), UIKit.color("plate"), 0.03, 2, { shadow = true, wood = 2 })
	f.Name = "Alert"
	f.ZIndex = 20
	UIKit.rect(f, UDim2.fromOffset(cw - 4, 1), UDim2.fromOffset(2, 1), color, 21)
	if icon then
		PixelSprites.image(f, icon, UDim2.fromOffset(4, math.floor((ch - 16) / 2)), 21)
	end
	UIKit.text(f, title, UDim2.fromOffset(cw - ix - 8, 10), UDim2.fromOffset(4 + ix, 3), { color = color, z = 21, name = "Title" })
	for i, l in lines do
		UIKit.text(f, l.text, UDim2.fromOffset(cw - ix - 8, 9), UDim2.fromOffset(4 + ix, 3 + 10 + (i - 1) * 9), { color = l.color or UIKit.color("text"), z = 21, name = "Line" .. i })
	end
	alertFrame = f
	UIKit.tween(f, 0.15, { Position = UDim2.fromOffset(x, y) })
	task.delay(AUTO_CARD, function()
		if f.Parent then
			UIKit.tween(f, 0.15, { Position = UDim2.fromOffset(x, y - 6) })
			task.wait(0.16)
			if f.Parent then
				f:Destroy()
			end
			if alertFrame == f then
				alertFrame = nil
			end
		end
	end)
end

-- A results card in the middle: lines, then a button.
local function resultCard(title: string, color: Color3, lines: { { text: string, color: Color3? } }, icon: string?, button: string, onClick: () -> ())
	local r = root
	if r == nil then
		return
	end
	local w, h = canvasSize()
	local cw = 180
	for _, l in lines do
		cw = math.max(cw, UIKit.textWidth(l.text) + 20)
	end
	cw = math.min(cw, w - 16)
	local ch = 22 + #lines * 10 + 22 + (if icon then 18 else 0)
	local x, y = math.floor((w - cw) / 2), math.floor((h - ch) / 2)
	local f = UIKit.plate(r, UDim2.fromOffset(cw, ch), UDim2.fromOffset(x, -ch - 8), UIKit.color("plate"), 0, 3, { shadow = true, wood = 3 })
	f.Name = "Result"
	f.ZIndex = 20
	UIKit.rect(f, UDim2.new(1, -6, 0, 2), UDim2.fromOffset(3, 1), color, 21)
	UIKit.text(f, title, UDim2.new(1, -8, 0, 16), UDim2.fromOffset(4, 4), { x = "center", face = "big", kind = "title", color = color, z = 21, name = "Title" })
	local ly = 22
	if icon then
		PixelSprites.image(f, icon, UDim2.fromOffset(math.floor(cw / 2) - 8, ly), 21)
		ly += 18
	end
	for i, l in lines do
		UIKit.text(f, l.text, UDim2.new(1, -8, 0, 10), UDim2.fromOffset(4, ly + (i - 1) * 10), { x = "center", color = l.color or UIKit.color("text"), z = 21, name = "Line" .. i })
	end
	local done = false
	local function go()
		if done then
			return
		end
		done = true
		f:Destroy()
		onClick()
	end
	local b = UIKit.button(f, button, UDim2.fromOffset(cw - 40, 14), UDim2.new(0, 20, 1, -18), go, { name = "ResultOk", color = UIKit.color("button_ok") })
	b.ZIndex = 22
	UIKit.tween(f, 0.22, { Position = UDim2.fromOffset(x, y) })
	task.delay(0.25, function()
		if f.Parent then
			UIKit.confetti(f, 20)
		end
	end)
end

playRound = function(data: { [string]: any })
	local events = if type(data.events) == "table" then data.events else {}
	playingSkill = type(events[1]) == "table" and events[1].t == "skill"
	for _, ev in events do
		if type(ev) == "table" and isOpen then
			playEvent(ev)
		end
	end
	playingSkill = false
	if not isOpen then
		return
	end
	local result = data.result
	if result then
		-- the battle is over: the view's numbers (on their way) take over from the shown ones
		table.clear(shownHp)
		table.clear(gaugeG)
		if aim or skillMenu then
			endAim(false)
		end
	end
	local st = stage
	if result == "win" then
		-- (no sound for a won fight: the party's jump for joy and the small alert say it)
		local order = 0
		for _, a in actors do
			if not a.foe then
				a.ko = false
				order += 1
				local who = a
				task.delay(order * 0.1, function()
					startMove(who, "victory")
				end)
				act(a, "cheer", 1.8)
			end
		end
		local lines: { { text: string, color: Color3? } } = {}
		table.insert(lines, { text = string.format("+%s xp for the party   +%s shells", Numbers.int(tonumber(data.xp) or 0), Numbers.int(tonumber(data.shells) or 0)), color = UIKit.color("good") })
		if type(data.ups) == "table" then
			for key, n in data.ups do
				table.insert(lines, { text = string.format("%s grew %d level%s!", nameOf(key), n, if n == 1 then "" else "s"), color = UIKit.color("accent") })
				-- a skill learnt on the way up (Data/Skills)
				local f = fighterOf(key)
				if f and type(n) == "number" then
					for _, d in Skills.learnt(Skills.lineOf(f.kind, f.skill), f.lvl, f.lvl + n) do
						table.insert(lines, { text = string.format("%s learnt %s!", nameOf(key), d.name), color = UIKit.color("accent") })
					end
				end
			end
		end
		local icon: string? = nil
		if type(data.friend) == "table" and type(data.friend.sp) == "string" then
			local d = Creatures.byId[data.friend.sp]
			icon = "icon_" .. data.friend.sp
			table.insert(lines, 1, { text = (if d then d.name else "A driftling") .. " joined your island!", color = UIKit.color("pink") })
		end
		if data.reward then
			table.insert(lines, 1, { text = string.format("The guardian is beaten! +%s shells", Numbers.int(tonumber(data.reward) or 0)), color = UIKit.color("accent") })
			if type(data.charted) == "number" then
				table.insert(lines, { text = string.format("Islands charted: %d", data.charted), color = UIKit.color("good") })
			end
			if st then
				for _ = 1, 3 do
					st.puff(st.at(0, 0, 2), "confetti")
				end
			end
			-- the path goes on: an alert, the party walks on (Sail home whenever the player likes)
			local n = tonumber(data.guardian) or 1
			local title = if data.first then (if isle then (isle :: Types.Isle).name .. " charted!" else "Charted!") else string.format("Guardian %d beaten!", n)
			alert(title, UIKit.color("accent"), lines, icon)
			refresh()
		else
			alert("Victory!", UIKit.color("good"), lines, icon)
			refresh()
		end
	elseif result == "lose" then
		Audio.play("sad")
		resultCard("The party fell...", UIKit.color("bad"), {
			{ text = "Everyone is back on their feet at home." },
			{ text = "All the loot comes home with you.", color = UIKit.color("text_dim") },
		}, nil, "Sail home", goHome)
	elseif result == "fled" then
		refresh()
	elseif type(data.friend) == "table" and type(data.friend.sp) == "string" then
		-- befriended mid-battle (others still fighting)
		local d = Creatures.byId[data.friend.sp]
		UIKit.notice((if d then d.name else "A driftling") .. " joined your island!", UIKit.color("pink"), 3)
	end
end

playNode = function(data: { [string]: any })
	local st = stage
	if st == nil then
		return
	end
	local kind = data.kind
	if kind == "loot" then
		Audio.play("coin")
		say(string.format("Found %d food and %d wood!", tonumber(data.food) or 0, tonumber(data.wood) or 0), UIKit.color("good"))
		for _, a in actors do
			if not a.foe then
				act(a, "reach", 0.6)
			end
		end
		st.puff(st.at(-2, -1, 0.5), "debris", 8)
	elseif kind == "chest" then
		Audio.play("chest")
		task.delay(0.3, function()
			Audio.play("coins")
		end)
		say(string.format("A chest: %s shells!", Numbers.int(tonumber(data.shells) or 0)), UIKit.color("accent"))
		st.puff(st.at(-2, -1, 1), "spark", 12)
		for _, a in actors do
			if not a.foe then
				act(a, "cheer", 0.8)
			end
		end
	elseif kind == "rest" then
		Audio.play("sparkle")
		say("A quiet spot: the party rests.", UIKit.color("good"))
		for _, a in actors do
			if not a.foe then
				st.puff(actorAt(a) + Vector3.new(0, 1, 0), "heal", 6)
			end
		end
	elseif kind == "wild" then
		say("Wild driftlings!", UIKit.color("orange"))
	elseif kind == "boss" then
		say((if isle then (isle :: Types.Isle).bossName else "The guardian") .. " blocks the way!", UIKit.color("bad"), 2.4)
	end
	if kind == "wild" or kind == "boss" then
		-- a battle: paused till its wild ones have landed, then it runs (the timers start where the server put them)
		table.clear(shownHp)
		table.clear(gaugeG)
		if type(data.foes) == "table" then
			for _, f in data.foes do
				if type(f) == "table" and type(f.key) == "string" then
					gaugeG[f.key] = tonumber(f.gauge) or 0
				end
			end
		end
		spNow = 0
		gaugePaused = true
		gaugeAt = os.clock()
		runAt = os.clock() + (if kind == "boss" then 2.2 else 1.4)
	end
end

goHome = function()
	local e = exp()
	if e == nil then
		ExpeditionUI.close()
		return
	end
	-- the party on deck for the voyage home (the founder aside)
	local members: { Voyage.Member } = {}
	for _, f in e.party do
		if f.kind == "villager" and f.look then
			table.insert(members, { look = f.look })
		elseif f.kind == "pal" and f.sp then
			table.insert(members, { sp = f.sp })
		end
	end
	busy = true
	local res = ask("exp.home", {})
	if res.ok then
		local got = if type(res.data) == "table" then res.data.got else nil
		ExpeditionUI.close(function()
			busy = false
			Voyage.home(members, function()
				if type(got) == "table" then
					UIKit.notice(string.format("Home again: +%s shells, +%s food, +%s wood", Numbers.int(tonumber(got.shells) or 0), Numbers.int(tonumber(got.food) or 0), Numbers.int(tonumber(got.wood) or 0)), UIKit.color("good"), 4)
				end
				Audio.play("reward")
			end)
		end)
	else
		busy = false
		refresh()
	end
end

------------------------------------------------------------------ the overlay's layout
local function button(parent: Instance, text: string, x: number, y: number, w: number, color: Color3?, enabled: boolean, click: () -> (), name: string)
	local b = UIKit.button(parent, text, UDim2.fromOffset(w, 15), UDim2.fromOffset(x, y), click, { name = name, color = color, enabled = enabled and not busy })
	b.ZIndex = 11
end

-- A trim of planks across a bar (the header's bottom, the footer's top), 3 px from row `y`: an ink rule on the side
-- that faces the stage, a lit row and a plank row, seams between the planks.
local function trim(bar: Frame, w: number, y: number, top: boolean)
	local ink, hi, mid, lo = UIKit.color("ink"), UIKit.color("frame_hi"), UIKit.color("frame"), UIKit.color("frame_lo")
	local rows: { Color3 } = if top then { ink, hi, mid } else { hi, mid, ink }
	for i, c in ipairs(rows) do
		UIKit.rect(bar, UDim2.fromOffset(w, 1), UDim2.fromOffset(0, y + i - 1), c, 10).Name = "Trim"
	end
	local x = if top then 30 else 8
	while x < w do
		UIKit.rect(bar, UDim2.fromOffset(1, 2), UDim2.fromOffset(x, y + (if top then 1 else 0)), lo, 10).Name = "Trim"
		x += 52
	end
	UIKit.rect(bar, UDim2.fromOffset(w, 1), UDim2.fromOffset(0, y + (if top then 3 else -1)), lo, 10).Name = "Trim"
end

refresh = function()
	local r = root
	local e = exp()
	if r == nil or not isOpen then
		return
	end
	-- everything but the curtain, a results card and the narration is laid out again
	for _, c in r:GetChildren() do
		if c.Name ~= "Curtain" and c.Name ~= "Result" and c.Name ~= "Say" and c.Name ~= "Alert" and c.Name ~= "Timers" and c.Name ~= "AimPointer" and not c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	if e == nil then
		return
	end
	if stage then
		buildParty(e)
		buildFoes(e)
	end
	if e.battle == nil then
		snacksLeft = e.snacks or 0
	end
	table.clear(bars)
	local w, h = canvasSize()
	local def = Islets.list[e.isle.kind]
	-- the header: the island, the path, the loot, Back (below Roblox's top bar: its strip is the header's backdrop)
	local top = topInset()
	local back = UIKit.rect(r, UDim2.fromOffset(w, top), UDim2.fromOffset(0, 0), UIKit.color("ink"), 9)
	back.Name = "TopBar"
	back.BackgroundTransparency = 0.2
	-- the header: a board of dark driftwood, a trim of planks along its bottom (GAME_DESIGN 2: the island's looks)
	local head = UIKit.rect(r, UDim2.fromOffset(w, HEAD_H), UDim2.fromOffset(0, top), UIKit.color("plate"), 9)
	head.Name = "Header"
	head.BackgroundTransparency = 0.04
	trim(head, w, HEAD_H - 3, false)
	UIKit.rect(head, UDim2.fromOffset(w, 1), UDim2.fromOffset(0, HEAD_H - 4), UIKit.color(if def then def.color else "accent"), 10)
	UIKit.text(head, string.format("%s  Lv %d", e.isle.name, e.isle.lvl), UDim2.fromOffset(106, 10), UDim2.fromOffset(4, 1), { color = UIKit.color("accent"), z = 11, name = "Islet" })
	lootLine(head, e, 4, 10)
	-- the endless path: a window from a stop back to PATH_AHEAD ahead (the guardians' crowns shown), the stage number
	local i0 = math.max(1, e.node - 1)
	local i1 = e.node + PATH_AHEAD
	local path = Expedition.nodesTo(e.isle, i1)
	local stage = Expedition.stageOf(e.node)
	UIKit.text(head, string.format("Stage %d", stage), UDim2.fromOffset(44, 10), UDim2.fromOffset(110, 6), { color = UIKit.color("text"), z = 11, name = "Stage" })
	local px = math.max(156, math.floor(w / 2) - (i1 - i0 + 1) * 7)
	for i = i0, i1 do
		local kind = path[i]
		local done = e.done[i] == true
		local here = i == e.node
		local name = "mini_" .. kind
		if i > 1 then
			UIKit.rect(head, UDim2.fromOffset(2, 1), UDim2.fromOffset(px - 2, 10), if done then UIKit.color("accent") else UIKit.color("plate_light"), 10)
		end
		local img = PixelSprites.image(head, if done or here or kind == "boss" then name else "mini_wild_sil", UDim2.fromOffset(px, if here then 2 else 5), 11)
		img.Name = "Node" .. i
		if here then
			UIKit.rect(head, UDim2.fromOffset(11, 1), UDim2.fromOffset(px, 15), UIKit.color("accent"), 10).Name = "Here"
		end
		px += 13
	end
	button(head, "Back to island", w - 72, 3, 68, UIKit.color("plate_light"), true, function()
		ExpeditionUI.close()
	end, "BackToIsland")
	-- the party along the bottom
	-- the footer: the same board, its trim along the top; what it holds sits under the trim
	local footBoard = UIKit.rect(r, UDim2.fromOffset(w, FOOT_H), UDim2.fromOffset(0, h - FOOT_H), UIKit.color("plate"), 9)
	footBoard.Name = "FooterBoard"
	footBoard.BackgroundTransparency = 0.04
	trim(footBoard, w, 0, true)
	local foot = Instance.new("Frame")
	foot.Name = "Footer"
	foot.BackgroundTransparency = 1
	foot.BorderSizePixel = 0
	foot.Size = UDim2.fromOffset(w, FOOT_H - 3)
	foot.Position = UDim2.fromOffset(0, h - FOOT_H + 3)
	foot.ZIndex = 9
	foot.Parent = r
	local cw = math.min(CARD_W, math.floor((w - 112) / 2) - 3)
	for i, f in e.party do
		local col, rowI = (i - 1) % 2, (i - 1) // 2
		fighterCard(foot, f, 4 + col * (cw + 3), 2 + rowI * 20, cw, false)
	end
	-- the foes down the right, under the header (those still in the battle)
	local b = e.battle
	if b then
		local n = 0
		for _, f in foesLeft() do
			n += 1
			fighterCard(r, f, w - 86, top + HEAD_H + 2 + (n - 1) * 20, 82, true)
		end
	end
	-- the buttons
	local bx = w - 104
	local ax = bx - 74
	if e.over then
		button(foot, "Sail home", bx, 13, 100, UIKit.color("button_ok"), true, goHome, "SailHome")
	elseif b and aim then
		-- aiming: whom at, then go (or back to the battle)
		local a = aim :: Aim
		local d = if a.skill then Skills.byId[a.skill :: string] else nil
		local what = if d then d.name else "Snack"
		local whoName = if bars[a.who] then bars[a.who].name else "You"
		local who2 = if a.side == "foe" then "a wild one" elseif a.side == "down" then "one who is down" else "a member"
		local hint = string.format("pick %s, tap again to %s", who2, if a.kind == "snack" then "throw" else "use")
		-- what is aimed and how, on a small plate over the middle of the footer (the cards keep their room on a phone)
		local line1 = string.format("%s: %s", what, whoName)
		local tw = math.min(w - 8, math.max(UIKit.textWidth(line1), UIKit.textWidth(hint)) + 14)
		local tip = UIKit.plate(r, UDim2.fromOffset(tw, 25), UDim2.fromOffset(math.floor((w - tw) / 2), h - FOOT_H - 29), UIKit.color("plate"), 0.08, 2)
		tip.Name = "AimTip"
		tip.ZIndex = 10
		UIKit.text(tip, line1, UDim2.fromOffset(tw, 10), UDim2.fromOffset(0, 2), { x = "center", color = UIKit.color("accent"), z = 11, name = "AimWhat" })
		UIKit.text(tip, hint, UDim2.fromOffset(tw, 10), UDim2.fromOffset(0, 13), { x = "center", color = UIKit.color("text_dim"), z = 11, name = "AimHint" })
		button(foot, if a.kind == "snack" then "Throw!" else "Use!", bx, 4, 100, UIKit.color("button_ok"), a.target ~= nil, function()
			task.spawn(useAim)
		end, "Aim_use")
		button(foot, "Back", bx, 22, 100, UIKit.color("plate_light"), true, function()
			endAim(true)
		end, "Aim_back")
	elseif b then
		-- the battle runs by itself: a snack (a few a trip), the skill window, or run
		local snackOk = not b.boss and snacksLeft > 0
		button(foot, string.format("Snack x%d", snacksLeft), ax, 4, 70, UIKit.color("pink"), snackOk, startSnack, "Act_snack")
		button(foot, "Flee", ax, 22, 70, UIKit.color("button_warn"), not b.boss, function()
			task.spawn(flee)
		end, "Act_flee")
		button(foot, "Skills", bx, 4, 100, UIKit.color("accent"), true, openSkills, "Act_skills")
		-- the skill points charging (the frame loop fills it)
		local spf = UIKit.plate(foot, UDim2.fromOffset(100, 15), UDim2.fromOffset(bx, 22), UIKit.color("plate_light"), 0, 2)
		spf.Name = "SpBar"
		spf.ZIndex = 11
		local fill = UIKit.rect(spf, UDim2.fromOffset(0, 3), UDim2.fromOffset(2, 10), UIKit.color("accent"), 12)
		fill.Name = "Fill"
		UIKit.text(spf, "", UDim2.fromOffset(100, 10), UDim2.fromOffset(0, 1), { x = "center", color = UIKit.color("text"), z = 13, name = "Label" })
		if skillMenu then
			skillWindow(r, e)
		end
	else
		-- between stops the party walks on by itself: a bar fills toward the next stop (Space or a tap on it: at once)
		local plate = Instance.new("TextButton")
		plate.Name = "AutoGo"
		plate.Text = ""
		plate.AutoButtonColor = false
		plate.BackgroundTransparency = 1
		plate.Size = UDim2.fromOffset(100, 15)
		plate.Position = UDim2.fromOffset(bx, 4)
		plate.ZIndex = 11
		plate.Parent = foot
		UIKit.plate(plate, UDim2.fromOffset(100, 15), UDim2.fromOffset(0, 0), UIKit.color("plate_light"), 0, 2).ZIndex = 11
		autoW = 96
		local fill = UIKit.rect(plate, UDim2.fromOffset(0, 2), UDim2.fromOffset(2, 11), UIKit.color("good"), 12)
		fill.Name = "Fill"
		autoFill = fill
		UIKit.text(plate, if busy then "Walking on..." elseif idleSince == math.huge then "Go on anyway" else "Next stop...", UDim2.fromOffset(100, 10), UDim2.fromOffset(0, 1), { x = "center", color = UIKit.color("text"), z = 12, name = "Label" })
		plate.Activated:Connect(function()
			idleSince = nil
			task.spawn(goOn)
		end)
		button(foot, "Sail home", bx, 22, 100, UIKit.color("button_warn"), true, goHome, "SailHome")
	end
	-- the wild ones' names stay on the cards; the stage's spots follow the fighters
	lastNode = e.node
end

------------------------------------------------------------------ open, close
function ExpeditionUI.isOpen(): boolean
	return isOpen
end

-- Whether an expedition is under way (the view's).
function ExpeditionUI.active(): boolean
	return exp() ~= nil
end

function ExpeditionUI.open()
	local e = exp()
	if isOpen then
		return
	end
	if e == nil then
		-- just set sail: the view with the expedition is on its way
		pendingOpen = os.clock() + 3
		return
	end
	pendingOpen = 0
	isOpen = true
	UIKit.closePanel()
	hideWorldUI(true)
	isle = e.isle
	local def = Islets.list[e.isle.kind]
	local canvas = UIKit.canvas("Stage")
	local w, h = canvasSize()
	local r = Instance.new("Frame")
	r.Name = "Expedition"
	r.BackgroundTransparency = 1
	r.BorderSizePixel = 0
	r.Size = UDim2.fromOffset(w, h)
	r.Parent = canvas
	root = r
	stage = MicroStage.open(if def then def.stage else "loot", { top = topInset() + HEAD_H + 2, bottom = FOOT_H + 2 }, e.isle.seed)
	actors = {}
	foeKey = ""
	-- the timers over the heads have their own layer (the layout's rebuilds leave it)
	local timers = Instance.new("Frame")
	timers.Name = "Timers"
	timers.BackgroundTransparency = 1
	timers.Size = UDim2.fromScale(1, 1)
	timers.ZIndex = 20
	timers.Parent = r
	table.clear(timerBars)
	table.clear(shownHp)
	table.clear(gaugeG)
	table.clear(playQueue)
	aim, skillMenu = nil, false
	snacksLeft = e.snacks or 0
	runAt = nil
	gaugePaused = true
	gaugeAt = os.clock()
	local b0 = e.battle
	if b0 then
		-- back to a battle under way (paused while the screen was closed): it runs again once the curtain lifts
		for _, list in { e.party, b0.foes } :: { { Types.Fighter } } do
			for _, f in list do
				gaugeG[f.key] = f.gauge or 0
			end
		end
		spNow = b0.sp or 0
		runAt = os.clock() + 0.8
	end
	lifted = false
	liftDelay = 0
	opened = os.clock()
	ship = nil
	if arriving and stage then
		-- the boat brings the party in: the drop from above happens behind the curtain, unseen
		local st = stage :: MicroStage.Stage
		st.lift()
		-- the boat at the player's boat level: its deck's places (along the bow: u; across: v)
		local v = view()
		local level = if v then v.boat else 1
		local d = BoatSpec.dims(level)
		shipU0 = SHIP_U - (d.L - 5) / 2
		deckH = BoatSpec.deckOverWater(level)
		DECK_SPOTS = {}
		for _, p in BoatSpec.deck(level) do
			table.insert(DECK_SPOTS, { p.Z, p.X, p.Y })
		end
		ship = st.spawn("ship", { level = level })
		st.place(ship :: MicroModels.Thing, SHIP_FROM, SHIP_V, WATER, MicroStage.FACE_RIGHT)
	end
	-- the founder stands with the party (MicroStage's own avatar)
	actors.f = newActor("f", false, PARTY_SPOTS[1])
	if arriving then
		actors.f.deck = 1
	end
	-- the curtain: ink blinds with the island's name while the stage's picture is baked
	local curtain = Instance.new("Frame")
	curtain.Name = "Curtain"
	curtain.BackgroundTransparency = 1
	curtain.Size = UDim2.fromScale(1, 1)
	curtain.ZIndex = 35
	curtain.Parent = r
	local BLIND = 12
	local blinds: { Frame } = {}
	for y = 0, h - 1, BLIND do
		local band = UIKit.rect(curtain, UDim2.fromOffset(w, math.min(BLIND, h - y)), UDim2.fromOffset(0, y), UIKit.color("ink"), 35)
		band.Name = "Blind"
		UIKit.rect(band, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), UIKit.hex(0x3B3048), 35)
		table.insert(blinds, band)
	end
	PixelSprites.image(curtain, "mini_boat", UDim2.fromOffset(math.floor(w / 2) - 5, math.floor(h / 2) - 26), 40)
	UIKit.text(curtain, e.isle.name, UDim2.fromOffset(w, 18), UDim2.fromOffset(0, math.floor(h / 2) - 12), { x = "center", face = "big", kind = "title", color = UIKit.color("accent"), z = 40, name = "IsletName" })
	UIKit.text(curtain, if def then string.format("A %s, level %d", string.lower(def.name), e.isle.lvl) else "", UDim2.fromOffset(w - 16, 10), UDim2.fromOffset(8, math.floor(h / 2) + 8), { x = "center", color = UIKit.color("text"), z = 40, name = "Blurb" })
	if not arriving then
		Audio.play("trumpet")
	end
	refresh()
	beat = RunService.Heartbeat:Connect(function(dt: number)
		local now = os.clock()
		if not lifted then
			local st = stage
			if st and ((st.ready() and now - opened >= 1.2) or now - opened > (stageWait or Tuning.StageWait)) then
				lifted = true
				liftDelay = now - opened
				st.lift()
				local mid = #blinds / 2
				for i, band in blinds do
					local d = math.abs(i - 0.5 - mid) * 0.018
					local y0 = band.Position.Y.Offset
					local bh = band.Size.Y.Offset
					task.delay(d, function()
						if band.Parent then
							UIKit.tween(band, 0.16, { Size = UDim2.fromOffset(w, 0), Position = UDim2.fromOffset(0, y0 + math.floor(bh / 2)) })
						end
					end)
				end
				task.delay(0.5, function()
					if curtain.Parent then
						curtain:Destroy()
					end
				end)
			end
		end
		poseAll(now - opened, math.min(dt, 0.1))
		-- going on by itself: at a stop with nothing to answer (no battle, no card, the party ashore)
		local cur = exp()
		local waiting = lifted and not busy and not closing and cur ~= nil and cur.battle == nil and cur.over == nil
		if waiting and root and (root :: Frame):FindFirstChild("Result") then
			waiting = false
		end
		if waiting then
			for _, a in actors do
				if a.deck > 0 then
					waiting = false
					break
				end
			end
		end
		if waiting then
			idleSince = idleSince or now
			local k = math.clamp((now - (idleSince :: number)) / AUTO_GO, 0, 1)
			local fill = autoFill
			if fill and fill.Parent then
				fill.Size = UDim2.fromOffset(math.floor(autoW * k), 2)
			end
			if k >= 1 then
				idleSince = nil
				task.spawn(goOn)
			end
		else
			idleSince = nil
		end
		-- the timed battle: the timers over the heads, the aim on the floor, the skill points' bar, and a new battle
		-- set running once its wild ones have landed
		updateTimers()
		updateAim()
		local spf = if root then (root :: Frame):FindFirstChild("SpBar", true) else nil
		if spf then
			local sp = spOf()
			local fill = spf:FindFirstChild("Fill")
			if fill and fill:IsA("Frame") then
				fill.Size = UDim2.fromOffset(math.floor(96 * sp / Tuning.SpMax), 3)
			end
			local label = spf:FindFirstChild("Label")
			if label and label:IsA("TextLabel") then
				local txt = string.format("SP %d/%d", math.floor(sp), Tuning.SpMax)
				if label:GetAttribute("Source") ~= txt then
					label:SetAttribute("Source", txt)
					UIKit.setText(label, txt)
				end
			end
		end
		local ra = runAt
		if ra and now >= ra and lifted and not closing and aim == nil and not skillMenu then
			runAt = nil
			if cur and cur.battle and not cur.over then
				setPaused(false)
			end
		end
		-- the pick left the battle (beaten, befriended, back up): the next one
		local am = aim
		if am and am.side ~= "none" then
			local still = false
			for _, f in candidates(am.side) do
				if f.key == am.target then
					still = true
				end
			end
			if not still then
				am.target = firstPick(am.side)
				if am.target == nil then
					endAim(true)
				else
					refresh()
				end
			end
		end
	end)
	-- the pointer on the stage while aiming: hover to pick (a mouse), tap or click someone to pick them, the pick
	-- again to go
	local downAt: Vector2? = nil
	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
	end
	table.insert(pointerConns, UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement and not processed and aim and lifted then
			local i, j = PixelRenderer.pixelAt(Vector2.new(input.Position.X, input.Position.Y))
			pointAt(i, j, false)
		end
	end))
	table.insert(pointerConns, UserInputService.InputBegan:Connect(function(input, processed)
		if isPress(input) then
			downAt = if processed or aim == nil then nil else Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	table.insert(pointerConns, UserInputService.InputEnded:Connect(function(input, _processed)
		if isPress(input) then
			local d = downAt
			downAt = nil
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if d and (pos - d).Magnitude < 16 and aim and lifted then
				local i, j = PixelRenderer.pixelAt(pos)
				pointAt(i, j, true)
			end
		end
	end))
	keys = UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not lifted or busy then
			return
		end
		local cur = exp()
		if cur == nil then
			return
		end
		local k = input.KeyCode
		if cur.battle then
			if aim then
				-- aiming: arrows switch the pick, Space / Return go, Escape / Backspace back
				if k == Enum.KeyCode.Left or k == Enum.KeyCode.Right or k == Enum.KeyCode.Up or k == Enum.KeyCode.Down or k == Enum.KeyCode.Tab then
					pickTarget(nil)
				elseif k == Enum.KeyCode.Space or k == Enum.KeyCode.Return then
					task.spawn(useAim)
				elseif k == Enum.KeyCode.Escape or k == Enum.KeyCode.Backspace then
					endAim(true)
				end
			elseif skillMenu then
				if k == Enum.KeyCode.Escape or k == Enum.KeyCode.Backspace then
					endAim(true)
				end
			elseif k == Enum.KeyCode.One or k == Enum.KeyCode.S then
				startSnack()
			elseif k == Enum.KeyCode.Two or k == Enum.KeyCode.K then
				openSkills()
			elseif k == Enum.KeyCode.Three or k == Enum.KeyCode.F then
				task.spawn(flee)
			end
		elseif not cur.over and (k == Enum.KeyCode.Space or k == Enum.KeyCode.Return) then
			task.spawn(goOn)
		end
	end)
	arriving = false
	ExpeditionUI.Changed:Fire(true)
end

-- Leave the screen: ink blinds close over the stage, then it goes and `after` runs (by default the blinds open on
-- the island: Voyage.reveal; Sail home: the voyage home).
function ExpeditionUI.close(after: (() -> ())?)
	if not isOpen or closing then
		return
	end
	-- a battle under way waits while the screen is closed
	local cur = exp()
	if cur and cur.battle and not cur.over then
		aim, skillMenu = nil, false
		DayLight.hold(nil)
		runAt = nil
		setPaused(true)
	end
	local r = root
	if r == nil then
		closeNow()
		return
	end
	closing = true
	local w, h = canvasSize()
	local curtain = Instance.new("Frame")
	curtain.Name = "LeaveCurtain"
	curtain.BackgroundTransparency = 1
	curtain.Size = UDim2.fromScale(1, 1)
	curtain.ZIndex = 45
	curtain.Parent = r
	local BLIND = 12
	local n = 0
	for y = 0, h - 1, BLIND do
		local bh = math.min(BLIND, h - y)
		local band = UIKit.rect(curtain, UDim2.fromOffset(w, 0), UDim2.fromOffset(0, y + math.floor(bh / 2)), UIKit.color("ink"), 45)
		UIKit.rect(band, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), UIKit.hex(0x3B3048), 45)
		n += 1
		task.delay(n * 0.01, function()
			if band.Parent then
				UIKit.tween(band, 0.16, { Size = UDim2.fromOffset(w, bh), Position = UDim2.fromOffset(0, y) })
			end
		end)
	end
	task.delay(0.4, function()
		closing = false
		closeNow()
		if after then
			after()
		else
			Voyage.reveal()
		end
	end)
end

closeNow = function()
	if not isOpen then
		return
	end
	isOpen = false
	idleSince, autoFill = nil, nil
	aim, skillMenu, aimMark, aimPath, aimRing, aimPointer, aimEndU, runAt = nil, false, nil, nil, nil, nil, nil, nil
	for _, c in pointerConns do
		c:Disconnect()
	end
	table.clear(pointerConns)
	DayLight.hold(nil)
	table.clear(timerBars)
	table.clear(playQueue)
	if beat then
		beat:Disconnect()
		beat = nil
	end
	if keys then
		keys:Disconnect()
		keys = nil
	end
	local st = stage
	stage = nil
	if st then
		st.close()
	end
	actors = {}
	table.clear(bars)
	local r = root
	root = nil
	if r then
		r:Destroy()
	end
	sayFrame = nil
	hideWorldUI(false)
	ExpeditionUI.Changed:Fire(false)
end

-- Set sail (Explore): the sailing cutscene, then the screen with the boat arriving (`keys`: the members picked).
function ExpeditionUI.sail(keys: { string }, isleNow: Types.Isle?)
	Voyage.play(keys, isleNow, function()
		-- (if the view with the expedition is still on its way, it opens, arriving, when it comes)
		arriving = true
		ExpeditionUI.open()
	end)
end

-- The battle's messages (the server runs it): its actions play back one after another, the timers sync.
local function enqueue(data: { [string]: any })
	table.insert(playQueue, data)
	if pumping then
		return
	end
	pumping = true
	task.spawn(function()
		while #playQueue > 0 do
			local d = table.remove(playQueue, 1)
			if isOpen and d then
				playRound(d)
			end
		end
		pumping = false
		if isOpen then
			refresh()
		end
	end)
end

function ExpeditionUI.init()
	Voyage.init()
	StateClient.Fx:Connect(function(msg: any)
		if type(msg) ~= "table" or msg.kind ~= "exp" or not isOpen then
			return
		end
		local data = msg.data
		if type(data) ~= "table" then
			return
		end
		if msg.step == "act" then
			takeGauges(data)
			enqueue(data)
		elseif msg.step == "timers" then
			takeGauges(data)
		end
	end)
	-- the view changed (the round's numbers settled, the expedition ended elsewhere): lay out again
	StateClient.Changed:Connect(function(v: Types.ClientView)
		if not isOpen then
			if v.exp ~= nil and os.clock() < pendingOpen then
				ExpeditionUI.open()
			end
			return
		end
		if v.exp == nil then
			if not busy then
				ExpeditionUI.close()
			end
			return
		end
		if not busy then
			refresh()
		end
	end)
end

-- Sims and previews: what is on screen, and the actions as a player would tap them (they yield).
function ExpeditionUI.debugState(): { [string]: any }
	local n = 0
	local aboard = 0
	for _, a in actors do
		n += 1
		if a.deck > 0 then
			aboard += 1
		end
	end
	local nt = 0
	for _ in timerBars do
		nt += 1
	end
	return {
		open = isOpen,
		lifted = lifted,
		actors = n,
		busy = busy,
		node = lastNode,
		foes = foeKey,
		ship = ship ~= nil,
		arrived = ship ~= nil and aboard == 0,
		timers = nt,
		paused = gaugePaused,
		sp = spOf(),
		snacks = snacksLeft,
		aim = if aim then (aim :: Aim).kind else nil,
		aimWho = if aim then (aim :: Aim).who else nil,
		aimTarget = if aim then (aim :: Aim).target else nil,
		marked = aimMark ~= nil,
		shown = (function(): string
			-- who stands on the stage now (not gone in a poof), their keys
			local keys: { string } = {}
			for key, ac in actors do
				if not ac.gone then
					table.insert(keys, key)
				end
			end
			table.sort(keys)
			return table.concat(keys, ",")
		end)(),
		arrow = (function(): number
			-- the arrow's dashes on the floor now (0: none; its length in dashes)
			local n2 = 0
			local t = aimPath
			if t then
				for name, part in (t :: MicroModels.Thing).parts do
					if string.sub(name, 1, 1) == "D" and part.Transparency < 0.95 then
						n2 += 1
					end
				end
			end
			return n2
		end)(),
		arrowGap = (function(): number?
			-- how far the arrow's end is from the pick (stage studs; nil: no arrow)
			local am = aim
			local tg = if am and (am :: Aim).target then actors[(am :: Aim).target :: string] else nil
			local eu = aimEndU
			if tg == nil or eu == nil then
				return nil
			end
			return math.sqrt((tg.u + tg.du - eu) ^ 2 + (tg.v + tg.dv - aimEndV) ^ 2)
		end)(),
		menu = skillMenu,
		queue = #playQueue,
		gauge = gaugeOf("f"),
		g0 = gaugeG.f,
		lock = gaugeLock,
		since = os.clock() - gaugeAt,
	}
end
function ExpeditionUI.debugWait(seconds: number?)
	stageWait = seconds
end
function ExpeditionUI.debugGo()
	goOn()
end
-- (the battle's moves as a player makes them: a snack at a wild one, a skill, run; aiming without going)
function ExpeditionUI.debugSnack(targetKey: string?)
	startSnack()
	if aim and targetKey then
		(aim :: Aim).target = targetKey
	end
	useAim()
end
function ExpeditionUI.debugSkill(who: string, id: string, targetKey: string?)
	openSkills()
	chooseSkill(who, id)
	if aim then
		if targetKey then
			(aim :: Aim).target = targetKey
		end
		useAim()
	end
end
function ExpeditionUI.debugFlee()
	flee()
end
function ExpeditionUI.debugAim(kind: string)
	if kind == "snack" then
		startSnack()
	elseif kind == "skills" then
		openSkills()
	else
		endAim(true)
	end
end
-- (the pointer over someone on the stage, as a mouse or a finger would be: `tap` false hovers, true taps; whether
-- it was over someone the aim can pick)
function ExpeditionUI.debugPoint(key: string, tap: boolean): boolean
	local st, a = stage, actors[key]
	if st == nil or a == nil then
		return false
	end
	local base = actorAt(a)
	local x, fy = (st :: MicroStage.Stage).screen(base)
	local _, hy = (st :: MicroStage.Stage).screen(base + Vector3.new(0, headOf(a), 0))
	return pointAt(x, math.floor((fy + hy) / 2), tap)
end
-- (where someone stands on the screen: art px)
function ExpeditionUI.debugScreenOf(key: string): (number, number)
	local st, a = stage, actors[key]
	if st == nil or a == nil then
		return -1, -1
	end
	local x, y = (st :: MicroStage.Stage).screen(actorAt(a))
	return x, y
end
function ExpeditionUI.debugHome()
	goHome()
end

return ExpeditionUI
