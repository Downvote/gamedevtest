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
local Traits = require(ReplicatedStorage.Shared.Data.Traits)
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
local FOOT_H = 47 -- the footer: a trim of planks along its top (3 px), then the commands and the party
-- The battle's boxes, the way the monster-catching games lay them out (GAME_DESIGN 7: "polish the battle experience
-- and interface"): the wild ones' boxes down the stage's top left (they stand at its top right), the party's along the
-- footer's right (they stand at its bottom left), the commands two by two at the footer's left.
local FOE_W = 104
local PARTY_W = 112
local CMD_W = 72
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
	style: Style?, -- its own attack (styleFor)
	spot: { number }, -- its place in an area (u, v from the area's middle)
	run: { u0: number, v0: number, u1: number, v1: number, t0: number, dur: number }?, -- running to its place (coming down the trail)
}

-- A battle move (GAME_DESIGN 7's expressive battles): its kind, when it began, how long it lasts and the gap it
-- closes or the way it is knocked (studs along and across the stage).
type Move = { kind: string, t0: number, dur: number, gu: number, gv: number }
-- A fighter's own attack (GAME_DESIGN 7: "make each character have a short unique attack animation ... they now attack
-- in place"): its style (by a driftling's body shape, or the person), its length, its blows (shares of the length),
-- how high it goes, which way it turns, and what flies to the target at the blow ("sparks", "twinkle", "pebble").
type Style = { kind: string, dur: number, hits: { number }, lift: number, turn: number, ranged: string? }
-- What a move does to its actor at a moment.
type MoveFrame = { du: number, dv: number, dy: number, tilt: CFrame, sq: Vector3, spin: number, action: string, k: number, mood: string, speed: number }

-- The shown health (the events move it; the view's numbers settle it after a round): `hp` where it is going, `shown`
-- where the bar has drained to (it runs down like a game's health bar), `lost` the pale part that lingers after a hit;
-- a party member's card also shows its timer (`gauge`) and the numbers; `x`, `y` its place (a hit jolts it).
type Bar = {
	hp: number,
	maxHp: number,
	name: string,
	lvl: number,
	card: Frame?,
	fill: Frame?,
	label: TextLabel?,
	w: number,
	shown: number,
	lost: number,
	lostAt: number,
	hitAt: number,
	ghost: Frame?,
	gauge: Frame?,
	gw: number,
	x: number,
	y: number,
	jolted: boolean,
	text: string,
	textAt: number, -- when the numbers were last redrawn (a new string is a new picture: a few a second)
	foe: boolean,
	out: boolean, -- a wild one's box gone (it slides out once its bar is empty)
}

local isOpen = false
local stage: MicroStage.Stage? = nil
local root: Frame? = nil
local actors: { [string]: Actor } = {}
local bars: { [string]: Bar } = {}
local prevBars: { [string]: Bar } = {} -- the boxes before the last layout (a bar keeps draining across it)
local busy = false
local walking = false -- busy only running on to the next stop: leaving stays open (any time: GAME_DESIGN 7)
local autoHeld = false -- (previews: the stops wait for a Go on instead of going on by themselves)
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
-- it comes in from behind the party (room space: +z, the screen's lower left) heading for the wild ones, and moors
-- with its bow in the foam (the stage's `landing`); SHIP_BACK studs further out when it sets off
local SHIP_X = -2.5
local SHIP_BACK = 13
local shipZ0 = 24 -- where it moors (a longer boat a little further out)
local SHIP_IN = 1.0 -- seconds it glides in
local HOP_T, RUN = 0.4, 12 -- a hop off (seconds), then a run to the place (studs/s)
local shipLand = 4.5 -- the hop's length: from the deck over the bow onto the beach
local ARRIVE_CAM = 0.8 -- the arrival's camera: this many areas back (over the boat), then up with the party
local WATER = -0.45 -- the sea's surface on the stage (from the floor's top)
-- where the party stands on deck (room space x, z off the boat's middle, y), the founder first (UI/Voyage's deck)
local DECK_SPOTS = { { 0, 0.1, 0 }, { 0.75, -0.9, 0 }, { -0.75, -0.9, 0 }, { 0, -1.75, 0.5 } }
local deckH = 0.625 -- its deck over the sea
local closing = false
local lastNode = 0
local foeKey = "" -- the battle's foes shown (rebuilt when they change)
local boxesFor = "" -- the line-up whose boxes have slid in (a new one's slide in again)
local pendingOpen = 0 -- os.clock until which the screen opens as soon as the view has the expedition (just started)
-- going on by itself (GAME_DESIGN 7: "no need to click on go on"): at a stop with nothing to answer, the party walks on
-- to the next one after AUTO_GO seconds; a won battle's card goes after AUTO_CARD
local AUTO_GO = 0.2 -- (a breath between stops: GAME_DESIGN 7, "just go on to the next immediately")
local AUTO_CARD = 3
local idleSince: number? = nil
local dimNow = 0 -- the battle's spotlight on the background (0 .. 1: PixelRenderer.setDim)
local DIM_SECS = 0.45 -- the background darkens (or lightens again) over this long
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
local inspect: (key: string?) -> () = function(_key: string?) end -- (a fighter's details plate: below)
local leaveChoice: () -> () = function() end -- (the header's Back to island: sail home or leave it waiting, below)
local leaveFrame: Frame? = nil -- (its card, while it is up)
local pickTarget: (key: string?) -> () = function(_key: string?) end
local closeNow: () -> () = function() end

local function view(): Types.ClientView?
	return StateClient.view()
end

local fightToFight: (e: Types.Expedition) -> boolean -- (below: between two fights)
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
-- The battle's places (GAME_DESIGN 7: "fights should be shown in the same view as pokemon"): the party on the near
-- side, its back to the screen, the wild ones on the far side facing it (u, v from the area's middle; MicroStage's
-- room-space places).
local function spotsOf(list: { { number } }): { { number } }
	local out = {}
	for _, p in list do
		local u, v = MicroStage.uvOf(p[1], p[2])
		table.insert(out, { u, v })
	end
	return out
end
local PARTY_SPOTS = spotsOf(MicroStage.PARTY_XZ)
local FOE_SPOTS = spotsOf(MicroStage.FOE_XZ)
-- the party's way forward (u, v of one stud toward the wild ones); the wild ones face the other way
local FWD_U, FWD_V = MicroStage.uvOf(0, -1)
local function fwdOf(a: Actor): (number, number)
	if a.foe then
		return -FWD_U, -FWD_V
	end
	return FWD_U, FWD_V
end
-- Every stop plays out in the landing's area (GAME_DESIGN 7: "no need to make the party walk anymore, the creatures
-- will appear in a single area"): the party stays on the trail and each battle's wild ones come down it to them.
local baseU, baseV = 0, 0 -- the area's middle (u, v)
local runEnd = 0 -- os.clock() when the last of a battle's wild ones gets to its place
local ENTER_DIST = 16 -- a battle's wild ones come this far down the trail to their places (from out of sight)
local ENTER_SPEED = 12 -- studs a second
local HOLD_SECS = 0.45 -- a finger held this long on a fighter shows its details (UI: inspect)

-- the styles (lengths at an even tempo, blows as shares of them), by a driftling's shape; people by who they are.
-- Short and snappy: the timers are quick (Tuning.AtbTime), so a blow is over in about half a second
local STYLE_BASE: { [string]: { dur: number, hits: { number }, ranged: string? } } = {
	bounce = { dur = 0.44, hits = { 0.55 } },
	pounce = { dur = 0.48, hits = { 0.5 } },
	pinch = { dur = 0.48, hits = { 0.35, 0.62 } },
	roar = { dur = 0.52, hits = { 0.48 }, ranged = "sparks" },
	stomp = { dur = 0.52, hits = { 0.5 } },
	flare = { dur = 0.48, hits = { 0.5 }, ranged = "twinkle" },
	tailwhip = { dur = 0.48, hits = { 0.45 } },
	headbutt = { dur = 0.4, hits = { 0.45 } },
	peck = { dur = 0.44, hits = { 0.3, 0.5, 0.7 } },
	spin = { dur = 0.48, hits = { 0.55 }, ranged = "twinkle" },
	shellspin = { dur = 0.52, hits = { 0.6 } },
	dive = { dur = 0.52, hits = { 0.55 } },
	punch = { dur = 0.4, hits = { 0.45 } },
	kick = { dur = 0.44, hits = { 0.5 } },
	swing = { dur = 0.48, hits = { 0.5 } },
	sling = { dur = 0.48, hits = { 0.62 }, ranged = "pebble" },
	hop = { dur = 0.48, hits = { 0.55 } },
}
local SHAPE_STYLE: { [string]: string } = {
	blob = "bounce",
	seal = "bounce",
	bun = "pounce",
	frog = "pounce",
	crab = "pinch",
	drake = "roar",
	golem = "stomp",
	yeti = "stomp",
	jelly = "flare",
	moth = "flare",
	lizard = "tailwhip",
	wyrm = "tailwhip",
	mole = "headbutt",
	pup = "headbutt",
	owl = "peck",
	bird = "peck",
	sprite = "spin",
	snail = "shellspin",
	turtle = "shellspin",
	bat = "dive",
}
local PERSON_STYLES = { "kick", "swing", "sling", "hop" }
local function hashOf(text: string): number
	local h = 7
	for i = 1, #text do
		h = (h * 31 + string.byte(text, i)) % 1000003
	end
	return h
end
-- A fighter's attack: the founder punches; a villager kicks, swings, slings a pebble or hops, by name; a driftling
-- moves the way its body does, each kind at its own tempo and height and turning its own way.
local function styleFor(kind: string, sp: string?, who: string): Style
	local name, seed = "bounce", who
	if kind == "founder" then
		name, seed = "punch", "founder"
	elseif sp then
		local d = Creatures.byId[sp]
		name = SHAPE_STYLE[if d then d.shape else "blob"] or "bounce"
		seed = sp
	else
		name = PERSON_STYLES[hashOf(who) % #PERSON_STYLES + 1]
	end
	local h = hashOf(seed)
	local base = STYLE_BASE[name]
	local tempo = 0.88 + (h % 7) * 0.04
	return {
		kind = name,
		dur = base.dur / tempo,
		hits = base.hits,
		lift = 0.8 + (math.floor(h / 7) % 5) * 0.1,
		turn = if math.floor(h / 35) % 2 == 0 then 1 else -1,
		ranged = base.ranged,
	}
end

local function actorAt(a: Actor): Vector3
	local st = stage
	if st == nil then
		-- (the screen closed while an action was still playing: it finishes on nothing)
		return Vector3.zero
	end
	local r = a.run
	if r then
		-- running to its place: where it is on the way
		local e = math.clamp((os.clock() - r.t0) / r.dur, 0, 1)
		return st.at(r.u0 + (r.u1 - r.u0) * e, r.v0 + (r.v1 - r.v0) * e, 0)
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
		u = spot[1] + baseU,
		v = spot[2] + baseV,
		spot = spot,
		run = nil,
		du = 0,
		dy = 0,
		yaw = if foe then MicroStage.FACE_PARTY else MicroStage.FACE_FOES,
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
		style = nil,
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
		a.style = styleFor(f.kind, f.sp, f.name)
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
-- (the narration, for code above its definition)
local sayFwd: (text: string, color: Color3?, seconds: number?) -> () = function(_t: string, _c: Color3?, _s: number?) end

local function buildFoes(e: Types.Expedition)
	local b = e.battle
	local key = ""
	if b then
		-- (the stop's number too: the next battle's line-up can match the last one's exactly, and it stands elsewhere)
		key = tostring(e.node) .. "|"
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
		a.style = styleFor("wild", f.sp or "pebblit", f.name)
		a.dy = 0
		if lifted then
			-- they come running down the trail from out of sight, one a moment after another, to their places (the
			-- screen opened on a battle: they stand there already behind the curtain)
			local fu, fv = fwdOf(a)
			local t0 = os.clock() + (i - 1) * 0.22
			local dur = ENTER_DIST / ENTER_SPEED
			a.run = { u0 = a.u - fu * ENTER_DIST, v0 = a.v - fv * ENTER_DIST, u1 = a.u, v1 = a.v, t0 = t0, dur = dur }
			runEnd = math.max(runEnd, t0 + dur + 0.1)
		end
		a.enterAt = os.clock() + (i - 1) * 0.15
		actors[f.key] = a
	end
	Audio.play(if b.boss then "drumroll" else "pop")
	-- a rare sight: an epic or legendary wild one lands with its own words
	if not b.boss then
		for _, f in b.foes do
			local cd = if f.sp then Creatures.byId[f.sp :: string] else nil
			if cd and cd.rarity >= 4 then
				local rar = Traits.RARITY[cd.rarity]
				task.delay(0.6, function()
					if isOpen then
						sayFwd(string.format(if cd.rarity >= 5 then "That's a legendary %s." else "That's an epic %s.", cd.name), UIKit.color(rar.color), 2.2)
						Audio.play("fanfare")
					end
				end)
				break
			end
		end
	end
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
local MOVES: { [string]: number } = { attack = 0.45, bash = 0.66, quick = 0.46, zap = 0.6, hurt = 0.45, ko = 0.75, guard = 0.6, cast = 0.7, throw = 0.5, refuse = 0.7, happy = 1.0, flee = 0.7, stumble = 0.9, victory = 1.6 }
-- the blows' moments (seconds); a plain attack's come from the fighter's own style
local IMPACTS: { [string]: { number } } = { attack = { 0.2 }, bash = { 0.38 }, quick = { 0.1, 0.19, 0.28 }, zap = { 0.38 } }
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

-- The battle's own clock (GAME_DESIGN 7: "attacks are paused when you are selecting a skill or throwing a snack, even
-- if they are mid attack"): it stands still while the player chooses (the skill window, aiming, the leave card), so
-- the moves and the playback of an action freeze where they are; `cutPlay`: a snack cancelled the action playing (its
-- "cancel" event), which stops there. The playback waits by it (bwait).
local bclock = 0
local cutPlay = false
local function playHeld(): boolean
	return aim ~= nil or skillMenu or leaveFrame ~= nil
end
-- Wait `seconds` of the battle's time; true when the action playing was cut (or the screen closed) meanwhile.
local function bwait(seconds: number): boolean
	local untilT = bclock + seconds
	while bclock < untilT do
		if cutPlay or not isOpen then
			return true
		end
		task.wait()
	end
	return cutPlay or not isOpen
end

local function startMove(a: Actor, kind: string, other: Actor?)
	local gu, gv = 0, 0
	if other then
		local du, dv = other.u - a.u, other.v - a.v
		local d = math.sqrt(du * du + dv * dv)
		if kind == "hurt" or kind == "ko" then
			-- knocked away from the one who hit it (an attacker stays where it stands: no run up to the target)
			local fu, fv = fwdOf(a)
			gu, gv = if d > 0 then -du / d else -fu, if d > 0 then -dv / d else -fv
		end
	end
	local st = a.style
	local dur = if kind == "attack" and st then st.dur else MOVES[kind] or 0.5
	a.move = { kind = kind, t0 = bclock, dur = dur, gu = gu, gv = gv }
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
	local fu, fv = fwdOf(a)
	local f: MoveFrame = { du = 0, dv = 0, dy = 0, tilt = CFrame.identity, sq = SQ1, spin = 0, action = "stand", k = 0, mood = "idle", speed = 0 }
	local kind = mv.kind
	local gu, gv = mv.gu, mv.gv
	local function lean(d: number)
		f.du, f.dv = fu * d, fv * d
	end
	local function pitch(deg: number)
		f.tilt = CFrame.Angles(math.rad(deg), 0, 0)
	end
	local function squash(x: number, y: number)
		f.sq = Vector3.new(x, y, x)
	end
	local stl = a.style
	if kind == "attack" and stl then
		-- its own move, where it stands (no run up to the target): the blow at the style's first hit
		local k = math.clamp(e / stl.dur, 0, 1)
		local h = stl.hits[1]
		local lift, turn = stl.lift, stl.turn
		f.mood = "attack"
		local name = stl.kind
		if name == "bounce" then
			if k < 0.3 then
				local q = ease(k / 0.3)
				squash(1 + 0.2 * q, 1 - 0.2 * q)
				f.action = "windup"
			elseif k < h then
				local q = (k - 0.3) / (h - 0.3)
				f.dy = math.sin(q * math.pi) * 0.9 * lift
				lean(0.3 * q)
				squash(0.9, 1.12)
				f.action = "jump"
			else
				local q = phase(k, h, 1)
				squash(1.2 - 0.2 * q, 0.8 + 0.2 * q)
				lean(0.3 * (1 - ease(q)))
				f.action, f.k = "strike", 1 - q
			end
		elseif name == "pounce" then
			if k < 0.3 then
				local q = ease(k / 0.3)
				lean(-0.3 * q)
				squash(1 + 0.18 * q, 1 - 0.18 * q)
				pitch(-12 * q)
				f.action = "windup"
			elseif k < h then
				local q = (k - 0.3) / (h - 0.3)
				lean(-0.3 + 1.0 * q)
				f.dy = math.sin(q * math.pi) * 0.8 * lift
				pitch(-12 + 32 * q)
				squash(0.88, 1.14)
				f.action = "jump"
			else
				local q = phase(k, h, 1)
				lean(0.7 * (1 - ease(q)))
				pitch(20 * (1 - q))
				f.action, f.k = "strike", 1 - q
			end
		elseif name == "pinch" or name == "peck" then
			-- quick snaps at each blow: a lean in, the claws or the beak shut
			local jab = 0
			for _, hk in stl.hits do
				jab = math.max(jab, 1 - math.abs(k - hk) / 0.11)
			end
			lean((if name == "peck" then 0.4 else 0.2) * jab + 0.1 * math.sin(k * math.pi))
			pitch((if name == "peck" then 30 else 12) * jab)
			squash(1 + 0.1 * jab, 1 - 0.08 * jab)
			f.action, f.k = "strike", jab
		elseif name == "roar" or name == "headbutt" then
			local back = if name == "roar" then 0.38 else 0.3
			if k < back then
				local q = ease(k / back)
				lean(-0.3 * q)
				pitch(-22 * q)
				squash(0.95, 1 + 0.08 * q)
				f.action = "windup"
			elseif k < h then
				local q = easeIn((k - back) / (h - back))
				lean(-0.3 + (if name == "roar" then 0.65 else 0.85) * q)
				pitch(-22 + 50 * q)
				f.action, f.k = "strike", q
			else
				local q = phase(k, h, 1)
				lean((if name == "roar" then 0.35 else 0.55) * (1 - ease(q)))
				pitch(28 * (1 - q))
				squash(1 + 0.1 * (1 - q), 1 - 0.08 * (1 - q))
				f.action, f.k = "strike", 1 - q
			end
		elseif name == "stomp" or name == "hop" then
			local up = if name == "stomp" then 0.7 else 0.9
			if k < h then
				local q = k / h
				f.dy = (if q < 0.7 then ease(q / 0.7) else 1 - easeIn((q - 0.7) / 0.3)) * up * lift
				squash(0.9, 1.14)
				f.action = "jump"
			else
				local q = phase(k, h, 1)
				squash(1.3 - 0.3 * q, 0.7 + 0.3 * q)
				f.action, f.k = "strike", 1 - q
			end
		elseif name == "flare" then
			if k < h then
				local q = k / h
				local s2 = 1 + 0.25 * ease(q)
				f.sq = Vector3.new(s2, s2, s2)
				f.dy = 0.4 * q
				f.action, f.k = "cast", q
			else
				local q = phase(k, h, 1)
				local s2 = if q < 0.25 then 1.25 - 1.6 * q else 0.85 + 0.15 * phase(q, 0.25, 1)
				f.sq = Vector3.new(s2, s2, s2)
				f.dy = 0.4 * (1 - q)
				f.action, f.k = "strike", 1 - q
			end
		elseif name == "tailwhip" then
			-- a turn on the spot: the tail swings round at the blow, then back to face them
			f.spin = turn * (if k < h then math.pi * ease(k / h) else math.pi + math.pi * ease(phase(k, h, 1)))
			f.dy = math.sin(k * math.pi) * 0.25 * lift
			pitch(10 * math.sin(k * math.pi))
			f.action, f.k = "strike", math.max(0, 1 - math.abs(k - h) / 0.2)
		elseif name == "spin" or name == "shellspin" then
			f.spin = turn * (if name == "spin" then 4 else 3) * math.pi * (k * k * (3 - 2 * k))
			if name == "spin" then
				f.dy = math.sin(k * math.pi) * 0.5 * lift
			else
				local w = math.min(1, math.min(k, 1 - k) * 6)
				squash(1 + 0.15 * w, 1 - 0.25 * w)
			end
			lean(0.2 * math.max(0, 1 - math.abs(k - h) / 0.15))
			f.action, f.k = "strike", math.max(0, 1 - math.abs(k - h) / 0.2)
		elseif name == "dive" then
			if k < 0.4 then
				local q = ease(k / 0.4)
				f.dy = q * lift
				lean(-0.2 * q)
				f.action = "jump"
			elseif k < h then
				local q = easeIn((k - 0.4) / (h - 0.4))
				f.dy = lift * (1 - q)
				lean(-0.2 + 0.8 * q)
				pitch(35 * q)
				f.action, f.k = "strike", q
			else
				local q = phase(k, h, 1)
				lean(0.6 * (1 - ease(q)))
				pitch(35 * (1 - q))
				f.action, f.k = "strike", 1 - q
			end
		elseif name == "punch" then
			if k < 0.3 then
				local q = ease(k / 0.3)
				lean(-0.15 * q)
				f.action, f.k = "windup", q
			elseif k < h then
				local q = (k - 0.3) / (h - 0.3)
				lean(-0.15 + 0.45 * q)
				f.action, f.k = "strike", q
			else
				local q = phase(k, h, 1)
				lean(0.3 * (1 - ease(q)))
				f.action, f.k = if q < 0.6 then "strike" else "stand", 1
			end
		elseif name == "kick" or name == "swing" then
			local amt = if name == "kick" then 0.7 else 1.1
			if k < h then
				local q = ease(k / h)
				f.spin = -turn * amt * 0.5 * math.sin(q * math.pi * 0.5) + turn * amt * easeIn(q) * 1.2
				f.dy = if name == "kick" then math.sin(q * math.pi) * 0.35 else 0
				f.action, f.k = if q < 0.5 then "windup" else "strike", q
			else
				local q = phase(k, h, 1)
				f.spin = turn * amt * (0.7 - 0.7 * ease(q))
				f.action, f.k = "strike", 1 - q
			end
			lean(0.2 * math.sin(k * math.pi))
		elseif name == "sling" then
			lean(-0.1 * math.sin(k * math.pi))
			f.action, f.k = "throw", math.min(1, k / h)
		end
	elseif kind == "quick" then
		-- three quick jabs where it stands, a blur of afterimages
		local jab = 0
		for _, hk in IMPACTS.quick do
			jab = math.max(jab, 1 - math.abs(e - hk) / 0.06)
		end
		lean(0.45 * jab)
		pitch(25 * jab)
		squash(1 + 0.15 * jab, 1 - 0.1 * jab)
		f.action, f.k, f.mood, f.speed = "strike", jab, "attack", 0
	elseif kind == "bash" then
		-- a leap straight up and a slam where it stood
		local hit = IMPACTS.bash[1]
		if e < 0.18 then
			local k = ease(e / 0.18)
			squash(1 + 0.3 * k, 1 - 0.3 * k)
			pitch(-15 * k)
			f.action, f.mood = "windup", "attack"
		elseif e < hit then
			local k = phase(e, 0.18, hit)
			f.dy = math.sin(k * math.pi) * 1.8
			lean(0.3 * k)
			pitch(30 * k)
			squash(0.82, 1.22)
			f.action, f.mood, f.k = "jump", "attack", 0.5
		elseif e < hit + 0.14 then
			local k = phase(e, hit, hit + 0.14)
			lean(0.3)
			squash(1.3 - 0.3 * k, 0.7 + 0.3 * k)
			f.action, f.mood, f.k = "strike", "attack", 1
		else
			local k = ease(phase(e, hit + 0.14, mv.dur))
			lean(0.3 * (1 - k))
			f.action = if k < 0.95 then "strike" else "stand"
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
			f.du, f.dv = fu * 0.6 * math.sin(k * math.pi), fv * 0.6 * math.sin(k * math.pi)
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
		f.du, f.dv = -fu * 5 * easeIn(k), -fv * 5 * easeIn(k)
		f.action, f.speed, f.mood = "run", 30, "walk"
		if kind == "stumble" and e >= 0.35 then
			-- trips over its feet and scrambles back
			local b = phase(e, 0.35, mv.dur)
			local back = 5 * easeIn(phase(0.35, 0, 0.5)) * (1 - ease(b))
			f.du, f.dv = -fu * back, -fv * back
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
	local shipZ = shipZ0
	if sh then
		local e = math.clamp(since / SHIP_IN, 0, 1)
		local ease = 1 - (1 - e) * (1 - e)
		shipZ = math.floor((shipZ0 + SHIP_BACK * (1 - ease)) * 4 + 0.5) / 4
		local bob = if e >= 1 and math.floor(t * 1.5) % 2 == 0 then 0.125 else 0
		MicroModels.flutter(sh :: MicroModels.Thing, t)
		local su, sv = MicroStage.uvOf(SHIP_X, shipZ)
		st.place(sh :: MicroModels.Thing, su, sv, WATER + bob, MicroStage.FACE_FOES)
		do
			-- the camera starts back over the boat and comes up with the party once it hops off
			local k = math.clamp((since - SHIP_IN - 0.2) / 1.4, 0, 1)
			st.follow(-ARRIVE_CAM * (1 - k * k * (3 - 2 * k)))
		end
	end
	for _, a in actors do
		-- running to its place (a battle's wild ones coming down the trail): the legs going, a driftling bounding,
		-- dust now and then
		local r = a.run
		if r then
			local e = math.clamp((now - r.t0) / r.dur, 0, 1)
			if e >= 1 then
				a.run = nil
				st.puff(st.at(r.u1, r.v1, 0.2), "dust", 3)
			else
				local u, v = r.u0 + (r.u1 - r.u0) * e, r.v0 + (r.v1 - r.v0) * e
				local yaw = if a.foe then MicroStage.FACE_PARTY else MicroStage.FACE_FOES
				local moving = e > 0
				if a.founder then
					st.pose(u, v, 0, yaw, t, if moving then ENTER_SPEED else 0, "stand")
				elseif a.rival then
					(a.rival :: MicroStage.Rival).pose(u, v, 0, yaw, t, if moving then ENTER_SPEED else 0, "stand")
				elseif a.thing then
					local th = a.thing :: MicroModels.Thing
					MicroModels.animate(th, t + a.ph, "cheer", 0)
					local hop = if moving and math.floor(t * 10 + a.ph) % 2 == 0 then 0.375 else 0
					st.place(th, u, v, hop, yaw)
				end
				if moving and math.random() < dt * 6 then
					st.puff(st.at(u, v, 0.1), "dust", 1)
				end
				continue
			end
		end
		-- the party hops off the arriving boat onto the shore one after another and runs to its places
		if a.deck > 0 then
			local spot = DECK_SPOTS[a.deck] or DECK_SPOTS[#DECK_SPOTS]
			local du, dv = MicroStage.uvOf(SHIP_X + spot[1], shipZ + spot[2])
			local dh = WATER + deckH + spot[3]
			local k = since - (SHIP_IN + 0.1 + (a.deck - 1) * 0.35)
			local hu, hv = a.u, a.v
			local dx, dz = hu - du, hv - dv
			local dist = math.max(4, math.sqrt(dx * dx + dz * dz))
			local leap = math.min(shipLand, dist - 1)
			local lu, lv = du + dx / dist * leap, dv + dz / dist * leap
			local u, v, y, action, speed = du, dv, dh, if since > 0 then "cheer" else "stand", 0
			if k >= HOP_T then
				local frac = math.min(1, (k - HOP_T) * RUN / math.max(0.5, dist - leap))
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
				local yaw = if k >= 0 then math.atan2(dir.X, dir.Z) else MicroStage.FACE_FOES
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
			if frozen and not playHeld() then
				mv.t0 += dt
			end
			local e = bclock - mv.t0
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
sayFwd = say

-- A box's health bar as it stands: green over half, yellow over a fifth, red below; the pale part just lost behind it;
-- a party member's numbers counting with it.
local function drawBar(b: Bar)
	local fill = b.fill
	if fill == nil then
		return
	end
	local span = b.w - 2
	local k = b.shown / math.max(1, b.maxHp)
	local px = math.floor(span * k + 0.5)
	if b.shown > 0 then
		px = math.max(px, 1)
	end
	fill.Size = UDim2.fromOffset(px, 2)
	fill.BackgroundColor3 = if k > 0.5 then UIKit.color("good") elseif k > 0.2 then UIKit.color("accent") else UIKit.color("bad")
	local g = b.ghost
	if g then
		local gpx = math.floor(span * b.lost / math.max(1, b.maxHp) + 0.5)
		g.Visible = gpx > px
		g.Size = UDim2.fromOffset(math.max(0, gpx - px), 2)
		g.Position = UDim2.fromOffset(1 + px, 1)
	end
	local label = b.label
	local now = os.clock()
	if label and (b.shown == b.hp or now - b.textAt >= 0.12) then
		local t = string.format("%d/%d", math.floor(b.shown + 0.5), b.maxHp)
		if t ~= b.text then
			b.text = t
			b.textAt = now
			UIKit.setText(label, t)
			UIKit.setTextColor(label, if k > 0.2 then UIKit.color("text") else UIKit.color("bad"))
		end
	end
end

-- The health a box is going to (`instant`: there at once, a new box); a loss jolts the box and leaves its pale part.
local function setBar(key: string, hp: number, instant: boolean?)
	local b = bars[key]
	if b == nil then
		return
	end
	local before = b.hp
	b.hp = math.clamp(hp, 0, b.maxHp)
	shownHp[key] = b.hp
	if instant then
		b.shown, b.lost = b.hp, b.hp
	elseif b.hp < before then
		b.lost = math.max(b.lost, b.shown)
		b.lostAt = os.clock()
		b.hitAt = os.clock()
	end
	drawBar(b)
end

------------------------------------------------------------------ the timed battle
-- Every frame: the bars drain toward their health (the pale part follows a moment later), a box just hit jolts a
-- pixel side to side, a party member's timer fills (it blinks when full). (Above `gaugeOf`: it is passed in.)
local function updateBars(dt: number, gaugeAt: (key: string) -> number)
	local now = os.clock()
	for key, b in bars do
		local card = b.card
		if card == nil or card.Parent == nil then
			continue
		end
		local step = math.max(b.maxHp * 1.1, 8) * dt
		local moved = false
		if b.shown ~= b.hp then
			b.shown = if b.shown > b.hp then math.max(b.hp, b.shown - step) else math.min(b.hp, b.shown + step)
			moved = true
		end
		if b.lost < b.shown then
			b.lost = b.shown
			moved = true
		elseif b.lost > b.shown and now - b.lostAt > 0.4 then
			b.lost = math.max(b.shown, b.lost - step)
			moved = true
		end
		if moved then
			drawBar(b)
		end
		-- a wild one down: its box slides back out of the stage's corner once the bar has run dry
		if b.foe and not b.out and b.hp <= 0 and b.shown <= 0 and now - b.hitAt > 0.5 then
			b.out = true
			UIKit.tween(card, 0.2, { Position = UDim2.fromOffset(-FOE_W - 16, b.y) })
			continue
		end
		if b.out then
			continue
		end
		local since = now - b.hitAt
		if since < 0.24 then
			local jolt = if math.floor(since * 25) % 2 == 0 then 1 else -1
			card.Position = UDim2.fromOffset(b.x + jolt, b.y)
			b.jolted = true
		elseif b.jolted then
			b.jolted = false
			card.Position = UDim2.fromOffset(b.x, b.y)
		end
		local gauge = b.gauge
		if gauge then
			local g = math.clamp(gaugeAt(key), 0, 1)
			local gpx = if b.shown > 0 then math.floor(b.gw * g) else 0
			if gauge.Size.X.Offset ~= gpx then
				gauge.Size = UDim2.fromOffset(gpx, 1)
			end
			gauge.BackgroundColor3 = if g >= 1 and math.floor(now * 4) % 2 == 0 then UIKit.color("text") else UIKit.color("accent")
		end
	end
end

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
	-- (none while the party is still running up to the battle)
	local show = e ~= nil and e.battle ~= nil and lifted and st ~= nil and folder ~= nil and os.clock() >= runEnd
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

-- A driftling's mutations as pips (5x5: a 1 px ink outline, its tier's colour, a lit corner), right-aligned to `right`
-- at `y`, the best tier first; how wide they are (0 for none).
local function mutPips(parent: Instance, muts: { string }?, right: number, y: number, z: number): number
	local list = table.clone(muts or {})
	table.sort(list, function(a, b)
		local ma, mb = Traits.byId[a], Traits.byId[b]
		return (if ma then ma.tier else -1) > (if mb then mb.tier else -1)
	end)
	local n = 0
	for _, id in list do
		local m = Traits.byId[id]
		if m and n < Traits.MAX then
			local x = right - (n + 1) * 6 + 1
			local pip = UIKit.rect(parent, UDim2.fromOffset(5, 5), UDim2.fromOffset(x, y), UIKit.color("ink"), z)
			pip.Name = "Mut_" .. id
			local col = UIKit.color(Traits.TIER_COLOR[m.tier] or "text")
			UIKit.rect(pip, UDim2.fromOffset(3, 3), UDim2.fromOffset(1, 1), col, z + 1)
			UIKit.rect(pip, UDim2.fromOffset(1, 1), UDim2.fromOffset(1, 1), col:Lerp(Color3.new(1, 1, 1), 0.5), z + 2)
			n += 1
		end
	end
	return if n > 0 then n * 6 else 0
end

-- A list of mutations in words ("Savage, Swift, Lazy"), the best tier first, and the best tier's colour.
local function mutWords(muts: { string }?): (string, Color3)
	local list = table.clone(muts or {})
	table.sort(list, function(a, b)
		local ma, mb = Traits.byId[a], Traits.byId[b]
		return (if ma then ma.tier else -1) > (if mb then mb.tier else -1)
	end)
	local names: { string } = {}
	local best = -1
	for _, id in list do
		local m = Traits.byId[id]
		if m then
			table.insert(names, m.name)
			best = math.max(best, m.tier)
		end
	end
	return table.concat(names, ", "), UIKit.color(Traits.TIER_COLOR[math.max(best, 0)] or "text")
end

-- A fighter's box: its portrait or icon, its name and level, its mutations as pips, "HP" and its health bar; a party
-- member's also the numbers and its timer under the bar; a wild one's a mark beside it when it is the guardian or the
-- player has befriended one of its kind (`badge`). A tap picks it while aiming.
local function fighterCard(parent: Instance, f: Types.Fighter, x: number, y: number, w: number, foe: boolean, badge: string?): Frame
	local selected = aim ~= nil and (aim :: Aim).target == f.key
	local h = if foe then 18 else 20
	local card = UIKit.plate(parent, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y), if selected then UIKit.color("accent") else UIKit.color("plate_light"), 0.03, 2, { bevel = true })
	card.Name = "Card_" .. f.key
	card.ZIndex = 10
	local iy = math.floor((h - 16) / 2)
	if f.sp then
		PixelSprites.image(card, "icon_" .. (f.sp :: string), UDim2.fromOffset(1, iy), 11)
	elseif f.look then
		UIKit.portrait(card, f.look :: Types.Look, 16, UDim2.fromOffset(1, iy)).ZIndex = 11
	end
	-- (a rare wild one's name in its rarity's colour: Data/Traits)
	local cd = if f.sp then Creatures.byId[f.sp :: string] else nil
	local nameCol = if cd and cd.rarity >= 3 then UIKit.color((Traits.RARITY[cd.rarity] or Traits.RARITY[1]).color) else UIKit.color("text")
	local ink = if selected then UIKit.color("ink") else nil
	-- the top line: the name, its mutations as pips (the best tier first, a flaw red: which wild one is worth a snack),
	-- the level at the right
	local lv = "Lv" .. f.lvl
	local lvW = UIKit.textWidth(lv)
	UIKit.text(card, lv, UDim2.fromOffset(lvW + 2, 9), UDim2.fromOffset(w - lvW - 4, 0), { x = "right", color = ink or UIKit.color("text_dim"), kind = if selected then "plain" else nil, z = 11, name = "Lv" })
	local pipsW = mutPips(card, f.muts, w - lvW - 6, 2, 11)
	UIKit.text(card, f.name, UDim2.fromOffset(w - 24 - lvW - pipsW, 9), UDim2.fromOffset(19, 0), { color = ink or nameCol, kind = if selected then "plain" else nil, z = 11, name = "Name" })
	-- the second line: "HP", the bar (the pale part just lost behind the fill), a party member's numbers
	local tagW = UIKit.textWidth("HP") + 2
	UIKit.text(card, "HP", UDim2.fromOffset(tagW, 9), UDim2.fromOffset(19, 8), { color = ink or UIKit.color("orange"), kind = if selected then "plain" else nil, z = 11, name = "HpTag" })
	local numW = if foe then 0 else UIKit.textWidth(string.format("%d/%d", f.maxHp, f.maxHp)) + 3
	local bx = 19 + tagW + 1
	local bw = w - bx - 3 - numW
	local back = UIKit.rect(card, UDim2.fromOffset(bw, 4), UDim2.fromOffset(bx, 10), UIKit.color("ink"), 11)
	back.Name = "HpBack"
	local ghost = UIKit.rect(back, UDim2.fromOffset(0, 2), UDim2.fromOffset(1, 1), UIKit.color("text"), 12)
	ghost.Name = "HpLost"
	ghost.Visible = false
	local fill = UIKit.rect(back, UDim2.fromOffset(bw - 2, 2), UDim2.fromOffset(1, 1), UIKit.color("good"), 13)
	fill.Name = "HpFill"
	local label: TextLabel? = nil
	if not foe then
		label = UIKit.text(card, "", UDim2.fromOffset(numW, 9), UDim2.fromOffset(w - numW - 3, 8), { x = "right", color = ink or UIKit.color("text"), kind = if selected then "plain" else nil, z = 13, name = "Hp" })
	end
	-- a party member's timer, a thin line under the bar (it fills toward the member's next action)
	local gauge: Frame? = nil
	if not foe then
		local gback = UIKit.rect(card, UDim2.fromOffset(bw, 3), UDim2.fromOffset(bx, 15), UIKit.color("ink"), 11)
		gback.Name = "TimerBack"
		local gf = UIKit.rect(gback, UDim2.fromOffset(0, 1), UDim2.fromOffset(1, 1), UIKit.color("accent"), 12)
		gf.Name = "Timer"
		gauge = gf
	end
	if badge then
		PixelSprites.image(card, badge, UDim2.fromOffset(w + 1, math.floor((h - 11) / 2)), 11).Name = "Badge"
	end
	local hp = hpOf(f)
	local old = bars[f.key] or prevBars[f.key]
	bars[f.key] = {
		hp = hp,
		maxHp = f.maxHp,
		name = f.name,
		lvl = f.lvl,
		card = card,
		fill = fill,
		label = label,
		w = bw,
		-- (a box laid out again keeps its bar where it had drained to)
		shown = if old then old.shown else hp,
		lost = if old then old.lost else hp,
		lostAt = if old then old.lostAt else 0,
		hitAt = if old then old.hitAt else 0,
		ghost = ghost,
		gauge = gauge,
		gw = bw - 2,
		x = x,
		y = y,
		jolted = false,
		text = "",
		textAt = 0,
		foe = foe,
		out = false,
	}
	setBar(f.key, hp, old == nil)
	local _ = foe
	local pick = Instance.new("TextButton")
	pick.Name = "Pick"
	pick.Text = ""
	pick.BackgroundTransparency = 1
	pick.Size = UDim2.fromScale(1, 1)
	pick.ZIndex = 14
	pick.Parent = card
	-- its details: the mouse over the card, or a finger held on it (a hold is not a tap: no pick on its release)
	local held = false
	pick.MouseEnter:Connect(function()
		inspect(f.key)
	end)
	pick.MouseLeave:Connect(function()
		inspect(nil)
	end)
	pick.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch then
			held = false
			task.delay(HOLD_SECS, function()
				if pick.Parent and input.UserInputState == Enum.UserInputState.Begin then
					held = true
					inspect(f.key)
				end
			end)
		end
	end)
	pick.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch and held then
			inspect(nil)
		end
	end)
	pick.Activated:Connect(function()
		if held then
			held = false
			return
		end
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

local tutorialTip: (r: Frame, e: Types.Expedition, w: number, h: number) -> ()
local nextTutShine = 0 -- the tips' catching step: when the Snack button shines next
local playRound: (data: { [string]: any }) -> ()
local playNode: (data: { [string]: any }) -> ()

-- Between stops (GAME_DESIGN 7: "no need to make the party walk anymore, the creatures will appear in a single area"):
-- the party stays where it is; anyone knocked down gets back up in their place.
local function regroup()
	for _, a in actors do
		if a.foe or a.gone then
			continue
		end
		if a.ko then
			a.ko = false
			act(a, "cheer", 0.5)
		end
		a.move = nil
		a.deck = 0
		a.dy = 0
		a.run = nil
		a.u, a.v = a.spot[1] + baseU, a.spot[2] + baseV
		a.yaw = MicroStage.FACE_FOES
	end
end
local goHome: () -> ()

local function goOn()
	local cur = exp()
	if busy or cur == nil or cur.battle ~= nil or cur.over ~= nil then
		return -- (never off to the next stop in the middle of a battle, or once the trip is over)
	end
	busy = true
	walking = true
	refresh()
	-- the next stop plays out where the party stands (a battle's wild ones come down the trail: buildFoes)
	regroup()
	Audio.play("tick")
	local res = ask("exp.next", {})
	if not walking then
		return -- left meanwhile (Sail home now, or the screen closed): that took over
	end
	walking = false
	if res.ok and type(res.data) == "table" and isOpen then
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
		UIKit.notice("The leader is down. No snacks until they're back up.", UIKit.color("bad"))
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

------------------------------------------------------------------ a fighter's details
-- (GAME_DESIGN 7: "allow players to see mutations and details of a creature in battle by hovering over it or holding
-- onto it on mobile") The mouse over a fighter (on the stage or its card), or a finger held on one for HOLD_SECS: a
-- plate over its head with its name (a driftling's in its rarity's colour) and level, what it is, its health and
-- stats, a driftling's passive and each of its mutations (its tier's colour and stars, what it gives).
local inspectKey: string? = nil
local inspectFrame: Frame? = nil

-- Whoever stands under a stage pixel (any side, standing or down), nearest the middle of their figure.
local function fighterAt(i: number, j: number): string?
	local st = stage
	if st == nil then
		return nil
	end
	local best: string? = nil
	local bestD = math.huge
	for key, ac in actors do
		if ac.gone or ac.deck > 0 or fighterOf(key) == nil then
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
				best, bestD = key, d
			end
		end
	end
	return best
end

-- Put the plate over its fighter's head (kept inside the screen, under the header); every frame while it shows.
local function placeInspect()
	local fr, key, st = inspectFrame, inspectKey, stage
	if fr == nil or key == nil or st == nil then
		return
	end
	local ac = actors[key]
	if ac == nil or ac.gone or fr.Parent == nil then
		inspect(nil)
		return
	end
	local w, h = canvasSize()
	local x, y = (st :: MicroStage.Stage).screen(actorAt(ac) + Vector3.new(0, headOf(ac) + 1.6, 0))
	local pw, ph = fr.Size.X.Offset, fr.Size.Y.Offset
	local px = math.clamp(math.floor(x - pw / 2), 4, w - pw - 4)
	local py = math.clamp(math.floor(y - ph), topInset() + HEAD_H + 2, h - FOOT_H - ph - 2)
	fr.Position = UDim2.fromOffset(px, py)
end

inspect = function(key: string?)
	if key == inspectKey and (key == nil or (inspectFrame and inspectFrame.Parent)) then
		return
	end
	inspectKey = key
	if inspectFrame then
		inspectFrame:Destroy()
		inspectFrame = nil
	end
	local r = root
	local f = if key then fighterOf(key) else nil
	if key == nil or f == nil or r == nil then
		inspectKey = nil
		return
	end
	local fi = f :: Types.Fighter
	local cd = if fi.sp then Creatures.byId[fi.sp :: string] else nil
	type Line = { text: string, color: Color3 }
	local lines: { Line } = {}
	local rar = if cd then Traits.RARITY[cd.rarity] or Traits.RARITY[1] else nil
	local what = if cd and rar then string.format("%s driftling%s", rar.name, if fi.kind == "wild" then " (wild)" else "") elseif fi.kind == "founder" then "The captain" else "A villager"
	table.insert(lines, { text = what, color = if rar then UIKit.color(rar.color) else UIKit.color("text_dim") })
	table.insert(lines, { text = string.format("HP %d/%d  ATK %d  DEF %d  SPD %d", math.max(0, math.floor(hpOf(fi) + 0.5)), fi.maxHp, fi.atk, fi.def, fi.spd), color = UIKit.color("text") })
	if cd then
		table.insert(lines, { text = cd.passive.name .. ": " .. Traits.describe(cd.passive.fx), color = UIKit.color("accent") })
		local muts = table.clone(fi.muts or {})
		table.sort(muts, function(a: string, b: string): boolean
			local ma, mb = Traits.byId[a], Traits.byId[b]
			return (if ma then ma.tier else -1) > (if mb then mb.tier else -1)
		end)
		if #muts == 0 then
			table.insert(lines, { text = "No mutations", color = UIKit.color("text_dim") })
		end
		for _, id in muts do
			local m = Traits.byId[id]
			if m then
				table.insert(lines, { text = string.format("%s%s %s", m.name, Traits.TIER_STARS[m.tier] or "", m.blurb), color = UIKit.color(Traits.TIER_COLOR[m.tier] or "text") })
			end
		end
	else
		local sk = Skills.byId[fi.skill]
		table.insert(lines, { text = "Skill: " .. (if sk then sk.name else (Creatures.skills[fi.skill] or fi.skill)), color = UIKit.color("accent") })
	end
	local title = fi.name
	local lv = "Lv" .. fi.lvl
	local pw = UIKit.textWidth(title) + UIKit.textWidth(lv) + 18
	for _, l in lines do
		pw = math.max(pw, UIKit.textWidth(l.text) + 10)
	end
	local w, _ = canvasSize()
	pw = math.min(pw, w - 8)
	local ph = 4 + 10 + #lines * 9 + 3
	local fr = UIKit.plate(r, UDim2.fromOffset(pw, ph), UDim2.fromOffset(0, 0), UIKit.color("plate"), 0.03, 2, { shadow = true, wood = 1 })
	fr.Name = "Inspect"
	fr.ZIndex = 30
	UIKit.text(fr, title, UDim2.fromOffset(pw - 10, 10), UDim2.fromOffset(4, 2), { color = if rar then UIKit.color(rar.color) else UIKit.color("accent"), z = 31, name = "InspectName" })
	UIKit.text(fr, lv, UDim2.fromOffset(UIKit.textWidth(lv) + 2, 10), UDim2.new(1, -UIKit.textWidth(lv) - 6, 0, 2), { x = "right", color = UIKit.color("text_dim"), z = 31 })
	for k, l in lines do
		UIKit.text(fr, l.text, UDim2.fromOffset(pw - 8, 10), UDim2.fromOffset(4, 3 + k * 9), { color = l.color, z = 31, name = "InspectLine" .. k })
	end
	inspectFrame = fr
	placeInspect()
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
-- What a skill's numbers do, in a line (Data/Skills' effects).
local function skillWhat(d: Skills.Skill): string
	local on = if d.all then "every wild one" else "one wild one"
	if d.dmg then
		if (d.hits or 1) > 1 then
			return string.format("%d hits, each %d%% of an attack, on %s.", d.hits :: number, math.floor((d.dmg :: number) * 100 + 0.5), on)
		end
		return string.format("%d%% of an attack on %s.", math.floor((d.dmg :: number) * 100 + 0.5), on)
	elseif d.revive then
		return string.format("Back up with %d%% health.", math.floor((d.revive :: number) * 100 + 0.5))
	elseif d.shield then
		local s = string.format("The team takes less harm for %d s.", d.shield :: number)
		if d.heal then
			s ..= string.format(" Mends %d%%.", math.floor((d.heal :: number) * 100 + 0.5))
		end
		return s
	elseif d.heal then
		return string.format("Mends %d%% of %s health.", math.floor((d.heal :: number) * 100 + 0.5), if d.all then "everyone's" else "their")
	elseif d.rally then
		return string.format("The team's attacks do %d%% more damage.", math.floor(((d.rally :: number) - 1) * 100 + 0.5))
	elseif d.haste then
		return if (d.haste :: number) >= 1 then "Every ally's timer fills right up." else string.format("Every ally's timer jumps %d%% of the way.", math.floor((d.haste :: number) * 100 + 0.5))
	elseif d.dizzy then
		return "Every wild one's timer goes back to empty."
	end
	return d.blurb
end
-- how a skill is aimed, said in the tip
local tipDebug: ((id: string) -> (boolean, { string }))? = nil -- (the open skill window's tip, as a hover shows it: debugSkillTip)
local AIM_SAYS: { [string]: string } = {
	none = "No aiming.",
	foe = "Pick a wild one.",
	ally = "Pick a member.",
	down = "Pick one who is down.",
}

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
	-- what a skill does, while the pointer is over it or a finger is on it ("show what skills do while hovering or
	-- pressing onto it", 2026-11-11): a small plate under the button (over it near the bottom). A finger held on it
	-- past HOLD_SECS only reads it: lifting it then doesn't use the skill.
	local tip: Frame? = nil
	local tipId: string? = nil
	local function hideTip(id: string?)
		if tip and (id == nil or tipId == id) then
			tip:Destroy()
			tip, tipId = nil, nil
		end
	end
	local function showTip(b: GuiObject, f: Types.Fighter, d: Skills.Skill, id: string)
		if tipId == id and tip and tip.Parent then
			return
		end
		hideTip()
		local lines: { { text: string, color: Color3 } } = {
			{ text = d.blurb, color = UIKit.color("text") },
			{ text = skillWhat(d), color = UIKit.color("text_dim") },
			{ text = "Used by " .. f.name .. ". " .. AIM_SAYS[d.target], color = UIKit.color("text_dim") },
		}
		local cost = string.format("%d SP", d.cost)
		local pw = UIKit.textWidth(d.name) + UIKit.textWidth(cost) + 18
		for _, l in lines do
			pw = math.max(pw, UIKit.textWidth(l.text) + 10)
		end
		local cw, ch = canvasSize()
		pw = math.min(pw, cw - 8)
		local ph = 4 + 10 + #lines * 9 + 3
		local k = math.max(1, UIKit.P())
		local ro = r.AbsolutePosition
		local bx = math.floor((b.AbsolutePosition.X - ro.X) / k + 0.5)
		local by = math.floor((b.AbsolutePosition.Y - ro.Y) / k + 0.5)
		local bh = math.floor(b.AbsoluteSize.Y / k + 0.5)
		local py = by + bh + 2
		if py + ph > ch - 4 then
			py = by - ph - 2
		end
		local fr = UIKit.plate(r, UDim2.fromOffset(pw, ph), UDim2.fromOffset(math.clamp(bx, 4, cw - pw - 4), math.max(2, py)), UIKit.color("plate"), 0.03, 2, { shadow = true, wood = 1 })
		fr.Name = "SkillTip"
		fr.ZIndex = 40
		UIKit.text(fr, d.name, UDim2.fromOffset(pw - 10, 10), UDim2.fromOffset(4, 2), { color = UIKit.color("accent"), z = 41, name = "TipName" })
		UIKit.text(fr, cost, UDim2.fromOffset(UIKit.textWidth(cost) + 2, 10), UDim2.new(1, -UIKit.textWidth(cost) - 6, 0, 2), { x = "right", color = UIKit.color("text_dim"), z = 41, name = "TipCost" })
		for i, l in lines do
			UIKit.text(fr, l.text, UDim2.fromOffset(pw - 8, 10), UDim2.fromOffset(4, 3 + i * 9), { color = l.color, z = 41, name = "TipLine" .. i })
		end
		tip, tipId = fr, id
	end
	-- (it goes with the window)
	win.Destroying:Connect(function()
		hideTip()
		tipDebug = nil
	end)
	local tipButtons: { [string]: { b: GuiObject, f: Types.Fighter, d: Skills.Skill } } = {}
	tipDebug = function(id: string): (boolean, { string })
		local tb = tipButtons[id]
		if tb == nil then
			return false, {}
		end
		showTip(tb.b, tb.f, tb.d, id)
		local texts: { string } = {}
		if tip then
			for _, c in (tip :: Frame):GetChildren() do
				if c:IsA("TextLabel") then
					table.insert(texts, c.Text)
				end
			end
		end
		return tip ~= nil, texts
	end
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
			local id = f.key .. "_" .. d.id
			local readOnly = false -- (held long enough to read: this press doesn't use it)
			local b = UIKit.button(holder, it.label, UDim2.fromOffset(it.bw, 15), UDim2.fromOffset(it.x - 2, it.y), function()
				if readOnly then
					readOnly = false
					return
				end
				hideTip()
				chooseSkill(f.key, d.id)
			end, { name = "Skill_" .. id, color = if ok then UIKit.color("accent") else nil, enabled = ok })
			b.ZIndex = 28
			tipButtons[id] = { b = b, f = f, d = d }
			b.MouseEnter:Connect(function()
				showTip(b, f, d, id)
			end)
			b.MouseLeave:Connect(function()
				hideTip(id)
			end)
			b.InputBegan:Connect(function(input: InputObject)
				if input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				readOnly = false
				showTip(b, f, d, id)
				local t0 = os.clock()
				task.delay(HOLD_SECS, function()
					if tipId == id and input.UserInputState ~= Enum.UserInputState.End and os.clock() - t0 >= HOLD_SECS - 0.01 then
						readOnly = true
					end
				end)
			end)
			b.InputEnded:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.Touch then
					hideTip(id)
				end
			end)
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
		local t0 = bclock
		local impacts = IMPACTS[kind]
		local moveDur = MOVES[kind] or 0.5
		local stl = if by and kind == "attack" then by.style else nil
		if stl then
			-- its own move: the blows at its style's moments
			impacts = {}
			for _, hk in stl.hits do
				table.insert(impacts, hk * stl.dur)
			end
			moveDur = stl.dur
		end
		if by then
			startMove(by, kind, to)
			-- the swing is heard as it starts (in place: no run up first), a bash's as it leaps
			if kind == "bash" then
				task.delay(0.1, function()
					Audio.play("whoosh_heavy")
				end)
			elseif kind ~= "zap" then
				Audio.play("whoosh")
			end
		else
			impacts = { 0.05 }
		end
		-- (on the battle's clock: frozen while the player chooses; true when the action was cut meanwhile)
		local function at(seconds: number): boolean
			return bwait(t0 + seconds - bclock)
		end
		-- a puff of dust where it pushes off, and the skills' own effects
		if by and kind ~= "zap" then
			if at(0.04) then
				return
			end
			st.puff(actorAt(by) + Vector3.new(0, 0.2, 0), "dust", if kind == "bash" then 10 else 4)
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
				if at(0.08 * j) then
					return
				end
				st.puff(actorAt(by) + Vector3.new(0, 1.2, 0), "spark", 4)
				if by.thing then
					st.flash(by.thing :: MicroModels.Thing, 0.05)
				end
			end
			if at(0.32) then
				return
			end
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
			if at(when) then
				return
			end
			-- a ranged style's flourish flies across at the blow: sparks from a roar, twinkles, a slung pebble
			local ranged = if stl then stl.ranged else nil
			if ranged and by and to and i == 1 then
				local p0, p1 = actorAt(by) + Vector3.new(0, 1.2, 0), actorAt(to) + Vector3.new(0, 1.2, 0)
				for j = 1, 5 do
					local q = j / 6
					local arc = if ranged == "pebble" then math.sin(q * math.pi) * 1.2 else 0
					st.puff(p0:Lerp(p1, q) + Vector3.new(0, arc, 0), if ranged == "sparks" then "spark" elseif ranged == "pebble" then "debris" else "twinkle", 1)
				end
			end
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
				local heavyStyle = stl ~= nil and (stl.kind == "stomp" or stl.kind == "hop")
				shake(if kind == "bash" or ev.ko or heavyStyle then 2 else 1, if kind == "bash" or heavyStyle then 0.25 else 0.14)
				freeze(if kind == "quick" then 0.03 else 0.05)
				t0 += if kind == "quick" then 0.03 else 0.05
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
		-- (the next action starts as this one's blow settles: the swing back home and the flinch play on under it)
		if at(math.max(impacts[#impacts] or 0, moveDur - 0.14) + 0.04) then
			return
		end
	elseif t == "heal" then
		local by, to = actors[ev.by], actors[ev.to]
		if not playingSkill then
			floatOver(ev.by, "Soothe!", UIKit.color("good"))
		end
		if by then
			startMove(by, "cast")
			st.puff(actorAt(by) + Vector3.new(0, 1.2, 0), "twinkle", 4)
		end
		if bwait(0.3) then
			return
		end
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
		if bwait(0.25) then
			return
		end
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
		if bwait(0.3) then
			return
		end
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
		say("Everyone goes at once.", UIKit.color("accent"), 1.2)
		Audio.play("whoosh", { pitch = 1.3 })
	elseif t == "dizzy" then
		for _, a in actors do
			if a.foe and not a.ko then
				startMove(a, "stumble")
				st.puff(actorAt(a) + Vector3.new(0, 2, 0), "twinkle", 4)
			end
		end
		say("The wild ones are seeing stars.", UIKit.color("accent"), 1.2)
		Audio.play("poof")
	elseif t == "cancel" then
		-- the action cut short: everyone back in place, the health as the server says it is again (a knock-out
		-- undone), the one interrupted saying so
		for _, a in actors do
			a.move = nil
		end
		if type(ev.hp) == "table" then
			for key, hp in ev.hp do
				if type(key) == "string" and type(hp) == "number" then
					setBar(key, hp)
					local a = actors[key]
					if a and hp > 0 then
						a.ko = false
						a.action = "stand"
					end
				end
			end
		end
		local by = actors[ev.by]
		if by then
			floatOver(ev.by, if by.foe then "Distracted!" else "Holds back", UIKit.color("text_dim"))
			startMove(by, "stumble")
		end
		Audio.play("pop", { pitch = 0.9 })
	elseif t == "treat" then
		local to = actors[ev.to]
		local f = actors.f
		if f then
			startMove(f, "throw")
		end
		floatOver("f", "Here, have a snack.", UIKit.color("text"))
		Audio.play("whoosh", { pitch = 1.3 })
		if bwait(0.3) then
			return
		end
		if f and to then
			-- the treat's arc: a trail of sparkles from the founder's hand to the wild one
			local p0, p1 = actorAt(f) + Vector3.new(0, 2.5, 0), actorAt(to) + Vector3.new(0, 1.5, 0)
			for j = 1, 5 do
				local q = j / 5
				st.puff(p0:Lerp(p1, q) + Vector3.new(0, math.sin(q * math.pi) * 2.5, 0), "twinkle", 1)
				if bwait(0.04) then
					return
				end
			end
		end
		if to then
			if ev.ok then
				st.puff(actorAt(to) + Vector3.new(0, 1.5, 0), "heart", 12)
				startMove(to, "happy")
				floatOver(ev.to, "<3", UIKit.color("pink"))
				Audio.play("fanfare")
				say(nameOf(ev.to) .. " wants to come home with you.", UIKit.color("pink"), 2)
				if bwait(0.7) then
					return
				end
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
			say("Couldn't get away.", UIKit.color("bad"), 1.4)
			Audio.play("deny")
		end
	end
	bwait(if t == "hit" then 0.15 else STEP)
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
	local cw = math.max(180, UIKit.textWidth(title, "big") + 24)
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
		if cutPlay then
			-- a snack cancelled this action while it played: it stops here (the next message says how things stand)
			playingSkill = false
			return
		end
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
				table.insert(lines, { text = string.format("%s is up %d level%s.", nameOf(key), n, if n == 1 then "" else "s"), color = UIKit.color("accent") })
				-- a skill learnt on the way up (Data/Skills)
				local f = fighterOf(key)
				if f and type(n) == "number" then
					for _, d in Skills.learnt(Skills.lineOf(f.kind, f.skill), f.lvl, f.lvl + n) do
						table.insert(lines, { text = string.format("%s learnt %s.", nameOf(key), d.name), color = UIKit.color("accent") })
					end
				end
			end
		end
		local icon: string? = nil
		if type(data.friend) == "table" and type(data.friend.sp) == "string" then
			local d = Creatures.byId[data.friend.sp]
			icon = "icon_" .. data.friend.sp
			table.insert(lines, 1, { text = (if d then d.name else "A driftling") .. " is coming home with you.", color = UIKit.color("pink") })
			local words, col = mutWords(data.friend.muts)
			if words ~= "" then
				table.insert(lines, 2, { text = "Born " .. words, color = col })
			end
		end
		if data.reward then
			table.insert(lines, 1, { text = string.format("Guardian beaten. +%s shells", Numbers.int(tonumber(data.reward) or 0)), color = UIKit.color("accent") })
			if type(data.charted) == "number" then
				table.insert(lines, { text = string.format("Islands charted: %d", data.charted), color = UIKit.color("good") })
			end
			if st then
				for _ = 1, 3 do
					st.puff(st.at(baseU, baseV, 2), "confetti")
				end
			end
			-- the path goes on: an alert, the party walks on (Sail home whenever the player likes)
			local n = tonumber(data.guardian) or 1
			local title = if data.first then (if isle then (isle :: Types.Isle).name .. " charted!" else "Charted!") else string.format("Guardian %d is down.", n)
			alert(title, UIKit.color("accent"), lines, icon)
			refresh()
		else
			alert("Victory!", UIKit.color("good"), lines, icon)
			refresh()
		end
	elseif result == "lose" then
		-- (GAME_DESIGN 7: "instead of the screen that says your party fell, say Expedition Complete! along with the
		-- resources you collected, and the xp and lvls gained from the expedition")
		Audio.play("reward")
		local loot = if type(data.loot) == "table" then data.loot else {}
		local gained = if type(data.gained) == "table" then data.gained else {}
		local lines: { { text: string, color: Color3? } } = {
			{ text = string.format("Shells +%s   Food +%s   Wood +%s", Numbers.int(tonumber(loot.shells) or 0), Numbers.int(tonumber(loot.food) or 0), Numbers.int(tonumber(loot.wood) or 0)), color = UIKit.color("good") },
			{ text = string.format("Party xp +%s", Numbers.int(tonumber(gained.xp) or 0)), color = UIKit.color("text") },
		}
		local ups = if type(gained.ups) == "table" then gained.ups else {}
		local keys: { string } = {}
		for key, n in ups do
			if type(key) == "string" and type(n) == "number" and n > 0 then
				table.insert(keys, key)
			end
		end
		table.sort(keys)
		for _, key in keys do
			local f = fighterOf(key)
			local n = ups[key] :: number
			local lv = if f then f.lvl else nil
			table.insert(lines, { text = if lv then string.format("%s: Lv %d to Lv %d", nameOf(key), lv - n, lv) else string.format("%s: +%d levels", nameOf(key), n), color = UIKit.color("accent") })
		end
		if #keys == 0 then
			table.insert(lines, { text = "No new levels this time.", color = UIKit.color("text_dim") })
		end
		resultCard("Expedition Complete!", UIKit.color("accent"), lines, nil, "Sail home", goHome)
	elseif result == "fled" then
		refresh()
	elseif type(data.friend) == "table" and type(data.friend.sp) == "string" then
		-- befriended mid-battle (others still fighting)
		local d = Creatures.byId[data.friend.sp]
		local words = mutWords(data.friend.muts)
		UIKit.notice((if d then d.name else "A driftling") .. " is coming home with you." .. (if words ~= "" then " (" .. words .. ")" else ""), UIKit.color("pink"), 3)
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
		say(string.format("Found %d food and %d wood.", tonumber(data.food) or 0, tonumber(data.wood) or 0), UIKit.color("good"))
		for _, a in actors do
			if not a.foe then
				act(a, "reach", 0.6)
			end
		end
		st.puff(st.at(baseU + FWD_U * -2, baseV + FWD_V * -2, 0.5), "debris", 8)
	elseif kind == "chest" then
		Audio.play("chest")
		task.delay(0.3, function()
			Audio.play("coins")
		end)
		say(string.format("A chest with %s shells in it.", Numbers.int(tonumber(data.shells) or 0)), UIKit.color("accent"))
		st.puff(st.at(baseU + FWD_U * -2, baseV + FWD_V * -2, 1), "spark", 12)
		for _, a in actors do
			if not a.foe then
				act(a, "cheer", 0.8)
			end
		end
	elseif kind == "rest" then
		Audio.play("sparkle")
		say("A quiet spot. The party gets its breath back.", UIKit.color("good"))
		for _, a in actors do
			if not a.foe then
				st.puff(actorAt(a) + Vector3.new(0, 1, 0), "heal", 6)
			end
		end
	elseif kind == "wild" then
		-- who it is, by name ("A wild Mossbun appeared.", "Wild Mossbun, Floe and Pebblit appeared.")
		local names: { string } = {}
		if type(data.foes) == "table" then
			for _, f in data.foes do
				if type(f) == "table" and type(f.name) == "string" then
					table.insert(names, f.name)
				end
			end
		end
		local who = if #names <= 1 then "A wild " .. (names[1] or "driftling") else "Wild " .. table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
		say(who .. " appeared.", UIKit.color("orange"), 2.2)
	elseif kind == "boss" then
		say((if isle then (isle :: Types.Isle).bossName else "The guardian") .. " is in the way.", UIKit.color("bad"), 2.4)
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
		-- (the skill points carry on from the last battle)
		spNow = tonumber(data.sp) or spNow
		gaugePaused = true
		gaugeAt = os.clock()
		-- (once they have come down the trail: a beat to take them in, longer for a guardian)
		runAt = math.max(os.clock(), runEnd) + (if kind == "boss" then 1.2 else 0.5)
	end
end

-- Back to island (the header's button, any time: GAME_DESIGN 7 "allow players to exit and return to the island at any
-- point"): a card over the screen, the battle paused and grey while it is up: Sail home (the trip ends here, a battle
-- left behind: everyone and all the loot come home), Leave it here (back to the island, the trip waits: the HUD's
-- card brings it back; not once the trip is over) or Stay.
leaveChoice = function()
	local r, e = root, exp()
	if e == nil then
		ExpeditionUI.close()
		return
	end
	if r == nil or leaveFrame or (busy and not walking) or closing then
		return
	end
	local battle = e.battle ~= nil and not e.over
	if aim or skillMenu then
		aim, skillMenu = nil, false
		updateAim()
		refresh()
	elseif battle then
		holdBattle(true)
	end
	local w, h = canvasSize()
	local cw = math.min(w - 16, 190)
	local over = e.over ~= nil
	local ch = if over then 52 else 70
	local f = UIKit.plate(r, UDim2.fromOffset(cw, ch), UDim2.fromOffset(math.floor((w - cw) / 2), math.floor((h - ch) / 2)), UIKit.color("plate"), 0.03, 2, { shadow = true, wood = 2 })
	f.Name = "LeaveCard"
	f.ZIndex = 40
	leaveFrame = f
	UIKit.text(f, if battle then "Leave the battle?" else "Head back?", UDim2.fromOffset(cw - 8, 10), UDim2.fromOffset(4, 3), { x = "center", color = UIKit.color("accent"), z = 41 })
	local function shut(resume: boolean)
		if leaveFrame == f then
			leaveFrame = nil
		end
		f:Destroy()
		if resume and battle then
			holdBattle(false)
		end
	end
	local y = 16
	local function choice(label: string, color: Color3, name: string, go: () -> ())
		local b = UIKit.button(f, label, UDim2.fromOffset(cw - 16, 14), UDim2.fromOffset(8, y), go, { name = name, color = color })
		b.ZIndex = 41
		y += 18
	end
	choice("Sail home now", UIKit.color("button_ok"), "LeaveHome", function()
		shut(false)
		DayLight.hold(nil)
		task.spawn(goHome)
	end)
	if not over then
		choice("Leave it here for now", UIKit.color("plate_light"), "LeaveWait", function()
			shut(false)
			ExpeditionUI.close()
		end)
	end
	choice("Stay", UIKit.color("plate_light"), "LeaveStay", function()
		shut(true)
	end)
	Audio.play("open")
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
	walking = false -- (a run on to the next stop is cut short: the trip ends here)
	busy = true
	local res = ask("exp.home", {})
	if res.ok then
		local got = if type(res.data) == "table" then res.data.got else nil
		ExpeditionUI.close(function()
			busy = false
			Voyage.home(members, function()
				if type(got) == "table" then
					UIKit.notice(string.format("Back home with %s shells, %s food and %s wood.", Numbers.int(tonumber(got.shells) or 0), Numbers.int(tonumber(got.food) or 0), Numbers.int(tonumber(got.wood) or 0)), UIKit.color("good"), 4)
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
	local free = not busy or (walking and name == "BackToIsland")
	local b = UIKit.button(parent, text, UDim2.fromOffset(w, 15), UDim2.fromOffset(x, y), click, { name = name, color = color, enabled = enabled and free })
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

-- The tips' fighting and catching steps (GAME_DESIGN 9: "make the tutorial also cover fighting, and catching
-- creatures"): a parchment note over the footer (not while aiming or choosing a skill: those have their own words),
-- worded for what is on the screen; the last step has its OK (`TutOk`, sending `tut.next`).
local TUT_TEXT: { [number]: { battle: string, boss: string?, calm: string } } = {
	[6] = {
		battle = "Fights run on their own. Each fighter acts when the bar over its head fills. Tap Skills to step in.",
		calm = "Your first island. The party walks on by itself, and there's a fight up ahead.",
	},
	[7] = {
		battle = "Want one? Wait till a wild one is hurt, then tap Snack, pick it and throw.",
		boss = "Guardians don't take snacks. Try again in the next fight.",
		calm = "In the next fight, tap Snack and throw one at a hurt wild one.",
	},
	[8] = {
		battle = "You made a friend. It will wait in a nest at home. Sail back whenever you want.",
		calm = "You made a friend. It will wait in a nest at home. Sail back whenever you want.",
	},
}
tutorialTip = function(r: Frame, e: Types.Expedition, w: number, h: number)
	local v = StateClient.view()
	local step = if v then TUT_TEXT[v.tut] else nil
	if step == nil or aim ~= nil or skillMenu or e.over then
		return
	end
	local b = e.battle
	local text = if b and b.boss and step.boss then step.boss :: string elseif b then step.battle else step.calm
	local ok = v ~= nil and v.tut == 8
	local room = w - 16
	local want = UIKit.textWidth(text) + (if ok then 42 else 14)
	local tw = math.min(want, room)
	local lines = if want > tw then 2 else 1
	local th = 4 + 10 * lines
	local f = UIKit.plate(r, UDim2.fromOffset(tw, th), UDim2.fromOffset(math.floor((w - tw) / 2), h - FOOT_H - th - 7), UIKit.color("paper"), 0, 2, { shadow = true, wood = 2 })
	f.Name = "TutTip"
	f.ZIndex = 12
	UIKit.text(f, text, UDim2.new(1, if ok then -38 else -10, 1, 0), UDim2.fromOffset(5, 0), { color = UIKit.color("text_ink"), kind = "plain", name = "Words", wrap = lines > 1, z = 13 })
	if ok then
		local bt = UIKit.button(f, "OK", UDim2.fromOffset(26, 10), UDim2.new(1, -29, 0, math.floor((th - 10) / 2)), function()
			task.spawn(function()
				StateClient.request("tut.next", {})
			end)
		end, { name = "TutOk" })
		bt.ZIndex = 13
	end
end

refresh = function()
	local r = root
	local e = exp()
	if r == nil or not isOpen then
		return
	end
	-- everything but the curtain, a results card and the narration is laid out again
	for _, c in r:GetChildren() do
		if c.Name ~= "Curtain" and c.Name ~= "Result" and c.Name ~= "Say" and c.Name ~= "Alert" and c.Name ~= "Timers" and c.Name ~= "AimPointer" and c.Name ~= "Inspect" and c.Name ~= "LeaveCard" and not c:IsA("TextLabel") then
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
	prevBars = bars
	bars = {}
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
		leaveChoice()
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
	-- the party's boxes two by two along the footer's right (the commands keep its left)
	local cmdW = 4 + 2 * CMD_W + 3
	local cw = math.min(PARTY_W, math.floor((w - cmdW - 10) / 2) - 2)
	local px0 = w - 4 - 2 * cw - 3
	for i, f in e.party do
		local col, rowI = (i - 1) % 2, (i - 1) // 2
		fighterCard(foot, f, px0 + col * (cw + 3), 1 + rowI * 22, cw, false)
	end
	-- the wild ones' boxes down the stage's top left (those still in the battle); a new battle's slide in from the
	-- edge one after another
	local b = e.battle
	if b then
		local v = StateClient.view()
		local n = 0
		local fresh = foeKey ~= boxesFor
		boxesFor = foeKey
		for _, f in foesLeft() do
			n += 1
			local badge = if b.boss and n == 1 then "mini_boss" elseif v and f.sp and v.seen[f.sp :: string] == 2 then "mini_nest" else nil
			local y = top + HEAD_H + 3 + (n - 1) * 20
			local card = fighterCard(r, f, 4, y, FOE_W, true, badge)
			if fresh then
				card.Position = UDim2.fromOffset(-FOE_W - 16, y)
				local delay = 0.25 + (n - 1) * 0.08
				task.delay(delay, function()
					if card.Parent then
						UIKit.tween(card, 0.22, { Position = UDim2.fromOffset(4, y) })
					end
				end)
			end
		end
	else
		boxesFor = ""
	end
	-- the commands, two by two at the footer's left: Skills and the skill points under it, Snack and Flee
	local ax = 4
	local bx = ax + CMD_W + 3
	local wide = 2 * CMD_W + 3
	if e.over then
		button(foot, "Sail home", ax, 14, wide, UIKit.color("button_ok"), true, goHome, "SailHome")
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
		-- a snack's pick: what it was born with (its mutations), so the player can choose whom to befriend
		local line3, col3 = "", UIKit.color("text_dim")
		if a.kind == "snack" and a.target then
			for _, f in b.foes do
				if f.key == a.target then
					local words, col = mutWords(f.muts)
					line3, col3 = if words ~= "" then f.name .. ": " .. words else f.name .. ": no mutations", if words ~= "" then col else UIKit.color("text_dim")
				end
			end
		end
		local tw = math.min(w - 8, math.max(UIKit.textWidth(line1), UIKit.textWidth(hint), UIKit.textWidth(line3)) + 14)
		local th = if line3 ~= "" then 34 else 25
		local tip = UIKit.plate(r, UDim2.fromOffset(tw, th), UDim2.fromOffset(math.floor((w - tw) / 2), h - FOOT_H - th - 4), UIKit.color("plate"), 0.08, 2)
		tip.Name = "AimTip"
		tip.ZIndex = 10
		UIKit.text(tip, line1, UDim2.fromOffset(tw, 10), UDim2.fromOffset(0, 2), { x = "center", color = UIKit.color("accent"), z = 11, name = "AimWhat" })
		if line3 ~= "" then
			UIKit.text(tip, line3, UDim2.fromOffset(tw, 10), UDim2.fromOffset(0, 11), { x = "center", color = col3, z = 11, name = "AimMuts" })
		end
		UIKit.text(tip, hint, UDim2.fromOffset(tw, 10), UDim2.fromOffset(0, th - 12), { x = "center", color = UIKit.color("text_dim"), z = 11, name = "AimHint" })
		button(foot, if a.kind == "snack" then "Throw!" else "Use!", ax, 5, wide, UIKit.color("button_ok"), a.target ~= nil, function()
			task.spawn(useAim)
		end, "Aim_use")
		button(foot, "Back", ax, 24, wide, UIKit.color("plate_light"), true, function()
			endAim(true)
		end, "Aim_back")
	elseif b then
		-- the battle runs by itself: a snack (a few a trip), the skill window, or run
		local snackOk = not b.boss and snacksLeft > 0
		button(foot, "Skills", ax, 5, CMD_W, UIKit.color("accent"), true, openSkills, "Act_skills")
		button(foot, string.format("Snack x%d", snacksLeft), bx, 5, CMD_W, UIKit.color("pink"), snackOk, startSnack, "Act_snack")
		button(foot, "Flee", bx, 24, CMD_W, UIKit.color("button_warn"), not b.boss, function()
			task.spawn(flee)
		end, "Act_flee")
		-- the skill points charging under Skills (the frame loop fills it)
		local spf = UIKit.plate(foot, UDim2.fromOffset(CMD_W, 15), UDim2.fromOffset(ax, 24), UIKit.color("plate_light"), 0, 2)
		spf.Name = "SpBar"
		spf.ZIndex = 11
		local fill = UIKit.rect(spf, UDim2.fromOffset(0, 3), UDim2.fromOffset(2, 10), UIKit.color("accent"), 12)
		fill.Name = "Fill"
		UIKit.text(spf, "", UDim2.fromOffset(CMD_W, 10), UDim2.fromOffset(0, 1), { x = "center", color = UIKit.color("text"), z = 13, name = "Label" })
		if skillMenu then
			skillWindow(r, e)
		end
	else
		-- between stops the next comes up at once (no bar to wait on): only Sail home
		button(foot, "Sail home", ax, 14, wide, UIKit.color("button_warn"), true, goHome, "SailHome")
	end
	tutorialTip(r, e, w, h)
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
	runEnd = 0
	stage = MicroStage.open(if def then def.stage else "loot", { top = topInset() + HEAD_H + 2, bottom = FOOT_H + 2 }, e.isle.seed, true)
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
		-- the boat at the player's boat level, its bow in the foam behind the party: its deck's places (it faces the
		-- wild ones, -z: its right, +x, is the room's -x and its bow, +z, the room's -z)
		local v = view()
		local level = if v then v.boat else 1
		local d = BoatSpec.dims(level)
		shipZ0 = st.landing(SHIP_X) + d.L / 2 - 0.75
		shipLand = d.L / 2 + 2
		deckH = BoatSpec.deckOverWater(level)
		DECK_SPOTS = {}
		for _, p in BoatSpec.deck(level) do
			table.insert(DECK_SPOTS, { -p.X, -p.Z, p.Y })
		end
		ship = st.spawn("ship", { level = level })
		local su, sv = MicroStage.uvOf(SHIP_X, shipZ0 + SHIP_BACK)
		st.place(ship :: MicroModels.Thing, su, sv, WATER, MicroStage.FACE_FOES)
		-- the picture opens over the boat (the camera comes up with the party: poseAll)
		st.follow(-ARRIVE_CAM, true)
	end
	-- the founder stands with the party (MicroStage's own avatar)
	actors.f = newActor("f", false, PARTY_SPOTS[1])
	actors.f.style = styleFor("founder", nil, "f")
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
		if not playHeld() then
			-- (actions waiting their turn: the playback goes a little quicker till it has caught up with the battle)
			local rate = 1 + 0.3 * math.min(#playQueue, 2)
			bclock += math.min(dt, 0.25) * rate
		end
		poseAll(now - opened, math.min(dt, 0.1))
		placeInspect()
		-- going on by itself: at a stop with nothing to answer (no battle, no card, the party ashore)
		local cur = exp()
		local waiting = lifted and not busy and not closing and not autoHeld and cur ~= nil and cur.battle == nil and cur.over == nil
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
			if now - (idleSince :: number) >= AUTO_GO then
				idleSince = nil
				task.spawn(goOn)
			end
		else
			idleSince = nil
		end
		-- a battle's spotlight: the background darkens round the fighters while it is on, and lightens after. It stays
		-- dark from a won fight to the next one, so going from fight to fight doesn't blink ("remove the flashing that
		-- happens after and before battles", 2026-11-11)
		local fighting = cur ~= nil and cur.over == nil and (cur.battle ~= nil or fightToFight(cur))
		local wantDim = if lifted and fighting and not closing then 1 else 0
		dimNow += math.clamp(wantDim - dimNow, -dt / DIM_SECS, dt / DIM_SECS)
		PixelRenderer.setDim(dimNow)
		-- the timed battle: the timers over the heads, the aim on the floor, the skill points' bar, and a new battle
		-- set running once its wild ones have landed
		updateTimers()
		updateBars(dt, gaugeOf)
		updateAim()
		-- the tips' catching step (GAME_DESIGN 9): the Snack button shines while a wild one is hurt
		local tv = StateClient.view()
		if tv and tv.tut == 7 and now >= nextTutShine and root then
			nextTutShine = now + 2
			local sb = (root :: Frame):FindFirstChild("Act_snack", true)
			if sb and sb:IsA("TextButton") and sb.AutoButtonColor then
				for _, f in foesLeft() do
					if hpOf(f) < f.maxHp * 0.5 then
						UIKit.shine(sb)
						break
					end
				end
			end
		end
		local spf = if root then (root :: Frame):FindFirstChild("SpBar", true) else nil
		if spf then
			local sp = spOf()
			local fill = spf:FindFirstChild("Fill")
			if fill and fill:IsA("Frame") then
				fill.Size = UDim2.fromOffset(math.floor((CMD_W - 4) * sp / Tuning.SpMax), 3)
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
		if ra and now >= ra and now >= runEnd and lifted and not closing and aim == nil and not skillMenu then
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
	local holdShown = false -- a finger held on a fighter showed its details: its release is not a tap
	table.insert(pointerConns, UserInputService.InputChanged:Connect(function(input, processed)
		if input.UserInputType == Enum.UserInputType.MouseMovement and not processed and lifted then
			local i, j = PixelRenderer.pixelAt(Vector2.new(input.Position.X, input.Position.Y))
			if aim then
				pointAt(i, j, false)
			end
			-- the mouse over a fighter: its details
			inspect(fighterAt(i, j))
		end
	end))
	table.insert(pointerConns, UserInputService.InputBegan:Connect(function(input, processed)
		if isPress(input) then
			downAt = if processed or aim == nil then nil else Vector2.new(input.Position.X, input.Position.Y)
		end
		if input.UserInputType == Enum.UserInputType.Touch and not processed and lifted then
			holdShown = false
			local at = Vector2.new(input.Position.X, input.Position.Y)
			task.delay(HOLD_SECS, function()
				local now = Vector2.new(input.Position.X, input.Position.Y)
				if isOpen and input.UserInputState == Enum.UserInputState.Begin and (now - at).Magnitude < 16 then
					local i, j = PixelRenderer.pixelAt(now)
					local key = fighterAt(i, j)
					if key then
						holdShown = true
						inspect(key)
					end
				end
			end)
		end
	end))
	table.insert(pointerConns, UserInputService.InputEnded:Connect(function(input, _processed)
		if isPress(input) then
			local d = downAt
			downAt = nil
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if holdShown then
				-- the details go with the finger; the hold was not a tap
				holdShown = false
				inspect(nil)
				return
			end
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
	if walking then
		-- left on the way to the next stop: the run is over (goOn lets go)
		walking = false
		busy = false
	end
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
	idleSince = nil
	dimNow = 0
	PixelRenderer.setDim(0)
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
	table.clear(prevBars)
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

-- Between two fights: the stop the party is at was a fight, now won, and the next one is a fight too.
local nextKey, nextFight = "", false
fightToFight = function(e: Types.Expedition): boolean
	local here = e.nodes[e.node]
	if (here ~= "wild" and here ~= "boss") or e.done[e.node] ~= true then
		return false
	end
	local key = tostring(e.isle.seed) .. ":" .. tostring(e.node)
	if key ~= nextKey then
		nextKey = key
		local i = e.node + 1
		local k = e.nodes[i] or Expedition.nodesTo(e.isle, i)[i]
		nextFight = k == "wild" or k == "boss"
	end
	return nextFight
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
			-- (the cut is for the action that was playing; the next message plays whole)
			cutPlay = false
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
	-- the battle's sounds loaded ahead: a swing or a blow is heard as it happens, never a moment after
	Audio.preload({ "whoosh", "whoosh_heavy", "hit", "hit_heavy", "bite", "zap", "body_fall", "pop", "heal", "shield", "poof", "combo", "sparkle" })
	StateClient.Fx:Connect(function(msg: any)
		if type(msg) ~= "table" or msg.kind ~= "exp" or not isOpen then
			return
		end
		local data = msg.data
		if type(data) ~= "table" then
			return
		end
		if msg.step == "act" then
			-- a snack thrown mid-action cancelled it (Battle.snack's "cancel"): what is playing stops at once
			if pumping and type(data.events) == "table" and type(data.events[1]) == "table" and data.events[1].t == "cancel" then
				cutPlay = true
			end
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
	local running, behind, foeU, dropping = 0, 0, nil, 0
	for _, a in actors do
		if a.run then
			running += 1
		end
		if a.foe and a.dy > 0 then
			dropping += 1
		end
		-- (along the road: studs toward the wild ones from the area's middle)
		local along = (a.u - baseU) * FWD_U + (a.v - baseV) * FWD_V
		if not a.foe and not a.gone and along < -20 then
			behind += 1
		end
		if a.foe and not a.gone then
			foeU = math.min(foeU or math.huge, along)
		end
	end
	return {
		open = isOpen,
		lifted = lifted,
		actors = n,
		busy = busy,
		area = 0, -- (every stop plays out in the landing's area)
		running = running, -- fighters still running to their places (a battle's wild ones coming down the trail)
		behind = behind, -- members of the party left more than 20 studs behind the area's middle
		foeU = foeU, -- the nearest wild one from the area's middle (along the road: they stand ahead of it)
		dropping = dropping, -- wild ones still dropping in from above
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
		clock = bclock, -- the battle's own clock (stands still while the player chooses)
		held = playHeld(),
		inspect = inspectKey,
		leave = leaveFrame ~= nil,
		tip = root ~= nil and (root :: Frame):FindFirstChild("TutTip") ~= nil,
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
-- (previews: hold the auto Go on, so a run to the next stop starts when they say)
function ExpeditionUI.debugAuto(on: boolean)
	autoHeld = not on
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
-- (the pointer resting on a skill in the open skill window, "<who>_<skill>" (e.g. "f_cry"): its tip shown; whether
-- it was there, and the tip's lines)
function ExpeditionUI.debugSkillTip(id: string): (boolean, { string })
	local fn = tipDebug
	if fn == nil then
		return false, {}
	end
	return fn(id)
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
-- (the details of whoever stands over that pixel, as the mouse over them shows them: the key shown, or nil; and the
-- plate's lines)
function ExpeditionUI.debugInspect(key: string?): (string?, { string })
	local st, a = stage, if key then actors[key] else nil
	if key == nil or st == nil or a == nil then
		inspect(nil)
	else
		local base = actorAt(a)
		local x, fy = (st :: MicroStage.Stage).screen(base)
		local _, hy = (st :: MicroStage.Stage).screen(base + Vector3.new(0, headOf(a), 0))
		inspect(fighterAt(x, math.floor((fy + hy) / 2)))
	end
	local lines: { string } = {}
	local fr = inspectFrame
	if fr then
		local name = fr:FindFirstChild("InspectName")
		if name and name:IsA("TextLabel") then
			table.insert(lines, name.Text)
		end
		for k = 1, 12 do
			local l = fr:FindFirstChild("InspectLine" .. k)
			if l and l:IsA("TextLabel") then
				table.insert(lines, l.Text)
			end
		end
	end
	return inspectKey, lines
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
