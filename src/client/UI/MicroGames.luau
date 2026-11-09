--!strict
-- The microgames (GAME_DESIGN 5; docs/ARCHITECTURE.md 10.8): twelve engines, each played by one or more ideas in
-- their own theme (Data/Ideas micro + variant), WarioWare style: a one-word order, a few seconds, win or lose. They
-- play out in 3D on the idea's stage (UI/MicroStage: a diorama room drawn full screen by the pixel filter) with the
-- player's own founder as the hero: they dodge falling crates, flip the pancake, pet the cat, walk the robot's
-- board, sneak past the ghost. An engine gets a context (the stage, the overlay frame for the words, pads and taps,
-- the difficulty 1..8 from the idea's rarity, the Turbo speed, Tiny, an Rng seeded by the server) and calls ctx.win()
-- or ctx.lose(); one that is `survive` wins when the clock runs out first; `after(t, won)` keeps the founder moving
-- (a cheer, a stumble) once it is over. MicroUI runs the clock, the effects and the modifiers' screen effects.
--
-- Stage space (MicroStage): u to the screen's right, v toward the viewer, y up from the floor. Things are world-
-- aligned parts on the iso grid (clean 2:1 edges, the world's ink outline); Tiny shrinks the targets.
--
-- Every button a sim can press has a name (Pad_<key>, Hole_<i>, Opt_<i>, Fruit_<i>); `auto` makes one right move (the
-- sims' player).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local MicroStage = require(script.Parent.MicroStage)

type Thing = MicroModels.Thing

export type Ctx = {
	area: Frame, -- the full-screen overlay (UI px = the world's art px)
	w: number,
	h: number,
	stage: MicroStage.Stage,
	rng: Types.Rng,
	diff: number, -- 1 .. Tuning.DiffMax
	speed: number, -- 1, or Tuning.TurboSpeed
	tiny: boolean, -- Tiny: the targets are small
	variant: string,
	pop: (x: number, y: number, text: string, color: Color3) -> (),
	burst: (x: number, y: number, colors: { string }, n: number?) -> (), -- 1 px bits fly out and fall
	float: (g: GuiObject, vx: number, vy: number, life: number, gravity: number?) -> (), -- moves it, then destroys it
	flash: (color: string) -> (), -- the screen flashes for a moment
	shake: () -> (),
	win: () -> (),
	lose: () -> (),
	press: (key: string) -> (), -- what a pad does (the runner routes it to the engine's key)
}

export type Micro = {
	update: (t: number, dt: number) -> (),
	key: (k: string) -> (), -- "left" | "right" | "up" | "down" | "go" | "1" .. "6"
	survive: boolean?, -- wins when the clock runs out (dodge, jump)
	clock: number?, -- the clock times this (the longer engines)
	after: ((t: number, won: boolean) -> ())?, -- once it is over: the founder's cheer or stumble
	auto: () -> (),
}

local Games = {}

local FACE = MicroStage.FACE_VIEWER
local RIGHT = MicroStage.FACE_RIGHT
local LEFT = MicroStage.FACE_LEFT
local AWAY = MicroStage.FACE_AWAY
local U_DIR, V_DIR = MicroStage.U_DIR, MicroStage.V_DIR

------------------------------------------------------------------ helpers
local function snap(v: number): number
	return math.floor(v + 0.5)
end

-- world-aligned room space (x, z from the floor's middle) -> stage space (u, v)
local function uvOf(x: number, z: number): (number, number)
	local p = Vector3.new(x, 0, z)
	return p:Dot(U_DIR), p:Dot(V_DIR)
end

-- the yaw that faces along a stage-space direction (du, dv)
local function yawTo(du: number, dv: number): number
	return math.atan2(du * U_DIR.X + dv * V_DIR.X, du * U_DIR.Z + dv * V_DIR.Z)
end

local function screenAt(ctx: Ctx, pos: Vector3): (number, number)
	local x, y = ctx.stage.screen(pos)
	return x, y
end

local function popAt(ctx: Ctx, pos: Vector3, text: string, color: string)
	local x, y = screenAt(ctx, pos)
	ctx.pop(x, y - 8, text, UIKit.color(color))
end

local function burstAt(ctx: Ctx, pos: Vector3, colors: { string }, n: number?)
	local x, y = screenAt(ctx, pos)
	ctx.burst(x, y, colors, n)
end

-- A target: small when Tiny.
local function target(ctx: Ctx, kind: string, opts: MicroModels.Opts?, shadow: number?): Thing
	local t = ctx.stage.spawn(kind, opts, shadow)
	if ctx.tiny then
		MicroModels.scale(t, Vector3.one * 0.6)
		t.h *= 0.6
		t.r *= 0.6
	end
	return t
end

-- The player's founder on the stage.
type Me = { u: number, v: number, y: number, yaw: number, action: string, k: number, speed: number }
local function newMe(u: number, v: number, yaw: number): Me
	return { u = u, v = v, y = 0, yaw = yaw, action = "stand", k = 0, speed = 0 }
end

local function pose(ctx: Ctx, m: Me, t: number)
	ctx.stage.pose(m.u, m.v, m.y, m.yaw, t, m.speed, m.action, m.k)
end

-- Once it is over: a cheer (turned to the viewer) or a stumble, back on the ground.
local function ending(ctx: Ctx, m: Me, t: number, won: boolean)
	m.action = if won then "cheer" else "hurt"
	m.speed = 0
	m.y = math.max(0, m.y - 0.25)
	if won then
		m.yaw = FACE
	end
	pose(ctx, m, t)
end

local WHITE = Color3.new(1, 1, 1)
local INK = UIKit.color("ink")

local function box(parent: Instance, w: number, h: number, x: number, y: number, color: string, z: number?): Frame
	return UIKit.rect(parent, UDim2.fromOffset(math.max(0, snap(w)), math.max(0, snap(h))), UDim2.fromOffset(snap(x), snap(y)), UIKit.color(color), z or 8)
end

-- A progress meter: a 1 px ink frame round a dark back, the fill with a lighter top row. Returns its setter (0..1).
local function meter(parent: Instance, x: number, y: number, w: number, h: number, color: string, z: number): (number) -> ()
	local back = UIKit.rect(parent, UDim2.fromOffset(w, h), UDim2.fromOffset(snap(x), snap(y)), INK, z)
	back.Name = "Meter"
	UIKit.rect(back, UDim2.fromOffset(w - 2, h - 2), UDim2.fromOffset(1, 1), UIKit.hex(0x463B5C), z)
	local c = UIKit.color(color)
	local fill = UIKit.rect(back, UDim2.fromOffset(0, h - 2), UDim2.fromOffset(1, 1), c, z)
	fill.Name = "Fill"
	UIKit.rect(fill, UDim2.new(1, 0, 0, 1), nil, c:Lerp(WHITE, 0.45), z)
	return function(frac: number)
		fill.Size = UDim2.fromOffset(math.floor((w - 2) * math.clamp(frac, 0, 1) + 0.5), h - 2)
	end
end

-- A touch pad: it presses `key`.
local function pad(ctx: Ctx, text: string, key: string, x: number, y: number, w: number, h: number, color: string?): TextButton
	local b = UIKit.button(ctx.area, text, UDim2.fromOffset(w, h), UDim2.fromOffset(snap(x), snap(y)), function()
		ctx.press(key)
	end, { name = "Pad_" .. key, color = UIKit.color(color or "plate_light") })
	b.ZIndex = 10
	return b
end

local PAD_Y = 18 -- the pads' row: this far above the screen's bottom edge (the fuse runs below it)

-- Arrow pads in a row at the bottom middle; each shows its 7 px arrow on the plate.
local function arrowPads(ctx: Ctx, keys: { string })
	local pw, ph = 28, 16
	local total = #keys * (pw + 3) - 3
	for i, k in keys do
		local b = pad(ctx, "", k, (ctx.w - total) / 2 + (i - 1) * (pw + 3), ctx.h - PAD_Y - ph, pw, ph)
		local plate = b:FindFirstChild("Plate") or b
		PixelSprites.image(plate, "arrow_" .. k .. "_t", UDim2.fromOffset(math.floor((pw - 7) / 2), math.floor((ph - 7) / 2)), 4)
	end
end

local function goPad(ctx: Ctx, text: string): TextButton
	return pad(ctx, text, "go", ctx.w / 2 - 32, ctx.h - PAD_Y - 16, 64, 16, "accent")
end

-- A one-line hint under the header.
local function say(ctx: Ctx, text: string, color: string?): TextLabel
	return UIKit.text(ctx.area, text, UDim2.fromOffset(ctx.w, 10), UDim2.fromOffset(0, 26), { x = "center", color = UIKit.color(color or "text"), kind = "outline", z = 12, name = "Say" })
end

-- A tap target with nothing drawn on it, kept over a point of the stage by follow().
local function hitbox(ctx: Ctx, name: string, w: number, h: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(w, h)
	b.ZIndex = 9
	b.Parent = ctx.area
	return b
end

local function follow(ctx: Ctx, b: GuiObject, pos: Vector3)
	local x, y = screenAt(ctx, pos)
	b.Position = UDim2.fromOffset(x - math.floor(b.Size.X.Offset / 2), y - math.floor(b.Size.Y.Offset / 2))
end

------------------------------------------------------------------ lanes: dodge and catch
-- Lanes across the screen (along u) in one row at depth v, each marked by a flat tile; the founder glides between
-- them.
local LANE = 3.5
type Lanes = { n: number, v: number, lane: () -> number, move: (d: number) -> (), u: (l: number) -> number, step: (dt: number) -> boolean }
local function lanes(ctx: Ctx, n: number, v: number, m: Me): Lanes
	local function laneU(l: number): number
		return (l - (n + 1) / 2) * LANE
	end
	for l = 1, n do
		local mark = ctx.stage.spawn("pad", { color = "plastic_dark" })
		MicroModels.scale(mark, Vector3.new(0.9, 0.2, 0.9))
		ctx.stage.place(mark, laneU(l), v, 0)
	end
	local lane = math.ceil(n / 2)
	m.u = laneU(lane)
	arrowPads(ctx, { "left", "right" })
	return {
		n = n,
		v = v,
		lane = function(): number
			return lane
		end,
		move = function(d: number)
			local nl = math.clamp(lane + d, 1, n)
			if nl ~= lane then
				ctx.stage.puff(ctx.stage.at(m.u, v, 0.2), "dust", 4)
			end
			lane = nl
		end,
		u = laneU,
		-- the founder glides to the lane; true while moving
		step = function(dt: number): boolean
			local tu = laneU(lane)
			local d = tu - m.u
			m.u += d * math.min(1, dt * 22)
			if math.abs(tu - m.u) < 0.05 then
				m.u = tu
			end
			return math.abs(d) > 0.2
		end,
	}
end

------------------------------------------------------------------ 1. dodge (Action "Dodge!", Racing "Steer!")
type Fall = { t: Thing, lane: number, y: number, v: number, gone: boolean, good: boolean, spin: number }
function Games.dodge(ctx: Ctx): Micro
	local st = ctx.stage
	local race = ctx.variant == "race"
	local n = if ctx.diff >= 7 then 5 elseif ctx.diff >= 4 then 4 else 3
	local row = if race then 6 else 2
	local m = newMe(0, row, if race then AWAY else FACE)
	local L = lanes(ctx, n, row, m)
	local kart = if race then st.spawn("kart", nil, 1.8) else nil
	local dashes: { Thing } = {}
	if race then
		for _ = 1, n - 1 do
			table.insert(dashes, st.spawn("dashes"))
		end
	end
	local items: { Fall } = {}
	local nextAt = 0.4
	local fall = (8 + 1.6 * ctx.diff) * ctx.speed -- studs a second
	local every = math.max(0.32, 0.8 - 0.06 * ctx.diff) / ctx.speed
	local TOP, FAR = 16, -18
	local dead = false
	say(ctx, if race then "Steer clear of the cones!" else "Dodge the falling crates!")
	-- how long until the nearest thing coming at a lane gets there: 0 or less while one is there, huge for none
	local function gapT(l: number): number
		local g = math.huge
		for _, it in items do
			if not it.gone and it.lane == l then
				local inZone = if race then it.v < row + 1.6 else it.y > 0.2
				if inZone then
					g = math.min(g, (if race then (row - 1.6 - it.v) else (it.y - 4.2)) / fall)
				end
			end
		end
		return g
	end
	local nextPuff = 0
	local function animate(t: number, dt: number)
		local moving = L.step(dt)
		m.speed = if moving and not race then 14 else 0
		m.action = if race then "reach" else "stand"
		m.y = if race then 0.75 else 0
		pose(ctx, m, t)
		if kart then
			st.place(kart, m.u, row, 0, AWAY)
			-- puffs from the exhaust
			if t >= nextPuff then
				nextPuff = t + 0.12
				st.puff(st.at(m.u + (math.random() - 0.5) * 0.6, row + 2, 0.5), "smoke", 1)
			end
		end
	end
	return {
		survive = true,
		update = function(t: number, dt: number)
			if dead then
				return
			end
			animate(t, dt)
			for i, d in dashes do
				st.place(d, (i - n / 2) * LANE, (t * fall) % 6, 0, FACE)
			end
			if t >= nextAt then
				nextAt = t + every * (0.7 + 0.6 * ctx.rng:next())
				-- never a wall: a lane stays open among the things just started
				local busy: { [number]: boolean } = {}
				local nBusy = 0
				for _, it in items do
					local fresh = if race then it.v < FAR + 8 else it.y > TOP - 7
					if not it.gone and fresh and not busy[it.lane] then
						busy[it.lane] = true
						nBusy += 1
					end
				end
				local l = ctx.rng:int(1, n)
				if nBusy < n - 1 or busy[l] then
					local th = target(ctx, if race then "cone" else "crate", nil, if race then 1.2 else 1.7)
					table.insert(items, { t = th, lane = l, y = if race then 0 else TOP, v = if race then FAR else row, gone = false, good = false, spin = 0 })
				end
			end
			for _, it in items do
				if not it.gone then
					if race then
						it.v += fall * dt
					else
						it.y -= fall * dt
					end
					st.place(it.t, L.u(it.lane), it.v, math.max(0, it.y))
					local hit = if race then it.lane == L.lane() and math.abs(it.v - row) < 1.6 else it.lane == L.lane() and it.y < 4.2 and it.y > 0.2
					if hit then
						dead = true
						st.flash(it.t, 0.3)
						burstAt(ctx, st.at(m.u, row, 2.5), { "white", "accent", "bad" }, 16)
						st.puff(st.at(m.u, row, 2.5), "spark", 12)
						ctx.shake()
						ctx.lose()
						return
					end
					if (not race and it.y <= 0) or (race and it.v > 14) then
						-- a crate smashes on the floor; a cone goes by
						it.gone = true
						if not race then
							burstAt(ctx, st.at(L.u(it.lane), row, 0.5), { "wood", "berry_red", "white" }, 7)
							st.puff(st.at(L.u(it.lane), row, 0.6), "debris", 9, if it.lane % 2 == 0 then "wood_dark" else "berry_red")
							st.puff(st.at(L.u(it.lane), row, 0.3), "dust", 5)
						end
						st.remove(it.t)
					end
				end
			end
		end,
		key = function(k: string)
			if k == "left" then
				L.move(-1)
			elseif k == "right" then
				L.move(1)
			end
		end,
		after = function(t: number, won: boolean)
			if race then
				m.action = "reach"
				pose(ctx, m, t)
			else
				ending(ctx, m, t, won)
			end
		end,
		auto = function()
			local here = L.lane()
			if gapT(here) > 0.55 then
				return
			end
			local best, bestGap = here, gapT(here)
			for l = 1, n do
				local g = gapT(l)
				local clear = true
				local step = if l > here then 1 else -1
				for k = here + step, l, step do
					if l ~= here and gapT(k) < 0.08 then
						clear = false
					end
				end
				if clear and (g > bestGap or (g == bestGap and math.abs(l - here) < math.abs(best - here))) then
					best, bestGap = l, g
				end
			end
			if best ~= here then
				L.move(if best > here then 1 else -1)
			end
		end,
	}
end

------------------------------------------------------------------ 2. timing (Cooking "Flip!", Sports "Kick!", RPG "Strike!")
-- A needle swings along a meter; press while it is in the green. Each hit plays out on the stage: the pancake flips
-- over the stove, the ball flies into the net, the founder dashes in and slashes the slime.
type Flight = { t0: number, dur: number, from: Vector3, to: Vector3, lift: number, turns: number, mode: string }
function Games.timing(ctx: Ctx): Micro
	local st = ctx.stage
	local v = ctx.variant
	local need = if ctx.diff >= 7 then 3 elseif ctx.diff >= 4 then 2 else 1
	local bw = math.min(220, ctx.w - 60)
	local bx, by = math.floor((ctx.w - bw) / 2), 40
	local zoneW = math.max(8, math.floor((40 - 4 * ctx.diff) * (if ctx.tiny then 0.5 else 1)))
	-- the meter
	local frame = UIKit.rect(ctx.area, UDim2.fromOffset(bw + 2, 10), UDim2.fromOffset(bx - 1, by - 1), INK, 8)
	frame.Name = "Meter"
	UIKit.rect(frame, UDim2.fromOffset(bw, 8), UDim2.fromOffset(1, 1), UIKit.hex(0x463B5C), 8)
	for x = 8, bw - 4, 8 do
		UIKit.rect(frame, UDim2.fromOffset(1, 2), UDim2.fromOffset(1 + x, 7), UIKit.hex(0x6E6488), 8)
	end
	local zone = UIKit.rect(ctx.area, UDim2.fromOffset(zoneW, 8), UDim2.fromOffset(bx, by), UIKit.color("good"), 9)
	zone.Name = "Zone"
	UIKit.rect(zone, UDim2.fromOffset(zoneW, 1), nil, UIKit.color("good"):Lerp(WHITE, 0.45), 9)
	UIKit.rect(zone, UDim2.fromOffset(1, 6), UDim2.fromOffset(math.floor(zoneW / 2), 1), UIKit.color("yellow"), 9)
	local needle = UIKit.rect(ctx.area, UDim2.fromOffset(3, 14), UDim2.fromOffset(bx, by - 3), INK, 10)
	needle.Name = "Needle"
	UIKit.rect(needle, UDim2.fromOffset(1, 12), UDim2.fromOffset(1, 1), WHITE, 10)
	local pos, dir = 0, 1
	local speed = (70 + 16 * ctx.diff) * ctx.speed
	local hits = 0
	local zx = 0
	-- the stage: the thing that flies (u, v, y at rest) and the founder
	local m: Me
	local thing: Thing? = nil
	local home = Vector3.zero
	local fly: Flight? = nil
	local swingUntil = 0
	local slime: Thing? = nil
	local slimeHit = -10
	local dashT = -10
	local SLIME_U, SLIME_V = 4, 3
	if v == "flip" then
		m = newMe(-4.5, 0, RIGHT)
		local pan = st.spawn("pan")
		st.place(pan, 0, 0, 3.25, FACE)
		home = Vector3.new(0, 0, 3.5)
		thing = target(ctx, "pancake")
	elseif v == "kick" then
		m = newMe(-1.75, 6.5, AWAY)
		home = Vector3.new(0, 4.5, 0)
		thing = target(ctx, "ball", nil, 0.8)
	else
		m = newMe(-6, SLIME_V, RIGHT)
		st.hold("sword")
		slime = target(ctx, "slime", nil, 1.5)
	end
	local count = say(ctx, string.format("Hit the green: 0/%d", need))
	local function placeZone()
		zx = ctx.rng:int(0, bw - zoneW)
		zone.Position = UDim2.fromOffset(bx + zx, by)
	end
	placeZone()
	local done = false
	local now = 0
	local function launch(to: Vector3, lift: number, dur: number, turns: number, mode: string)
		fly = { t0 = now, dur = dur, from = home, to = to, lift = lift, turns = turns, mode = mode }
	end
	local function hitFx()
		swingUntil = now + 0.25
		if v == "flip" then
			launch(home, 4, 0.45, 1, "home")
			burstAt(ctx, st.at(home.X, home.Y, home.Z + 0.5), { "yellow", "white", "orange" }, 8)
			st.puff(st.at(home.X, home.Y, home.Z + 0.6), "spark", 6)
			task.delay(0.45, function()
				st.puff(st.at(home.X, home.Y, home.Z + 0.4), "steam", 4)
			end)
		elseif v == "kick" then
			launch(Vector3.new(ctx.rng:int(-25, 25) / 10, MicroStage.GOAL_V - 0.5, 1), 3.5, 0.4, 0, "back")
			st.puff(st.at(home.X, home.Y, 0.3), "dust", 6)
			task.delay(0.4, function()
				burstAt(ctx, st.at(0, MicroStage.GOAL_V, 2.5), { "white", "good", "yellow" }, 14)
				st.puff(st.at(0, MicroStage.GOAL_V + 0.5, 2.5), "confetti", 18)
			end)
		elseif slime then
			dashT = now
			slimeHit = now + 0.12
			task.delay(0.12, function()
				local sl = slime
				if sl and sl.model.Parent then
					st.flash(sl, 0.12)
					burstAt(ctx, st.at(SLIME_U, SLIME_V, 1.5), { "green", "white", "leaf" }, 10)
					st.puff(st.at(SLIME_U, SLIME_V, 1.2), "debris", 8, "green")
					st.puff(st.at(SLIME_U - 1, SLIME_V, 1.6), "spark", 6)
				end
			end)
		end
	end
	local function press()
		if done then
			return
		end
		if pos >= zx - 1 and pos <= zx + zoneW + 1 then
			hits += 1
			Audio.play("pop", { pitch = 1 + hits * 0.15 })
			local perfect = math.abs(pos - (zx + zoneW / 2)) <= 2
			ctx.pop(bx + zx + zoneW / 2, by + 12, if perfect then "Perfect!" elseif v == "kick" then "Goal!" elseif v == "strike" then "Crit!" else "Flip!", UIKit.color(if perfect then "yellow" else "good"))
			hitFx()
			UIKit.setText(count, string.format("Hit the green: %d/%d", hits, need))
			if hits >= need then
				done = true
				local sl = slime
				if sl then
					task.delay(0.3, function()
						if sl.model.Parent then
							burstAt(ctx, st.at(SLIME_U, SLIME_V, 1), { "green", "leaf", "white" }, 20)
							st.puff(st.at(SLIME_U, SLIME_V, 1), "debris", 18, "green")
							st.puff(st.at(SLIME_U, SLIME_V, 0.5), "dust", 8)
							st.remove(sl)
							slime = nil
						end
					end)
				end
				ctx.win()
			else
				placeZone()
			end
		else
			done = true
			ctx.pop(bx + math.floor(pos), by + 12, "Miss!", UIKit.color("bad"))
			if v == "flip" then
				launch(Vector3.new(4, 3, 0), 3, 0.5, 2, "stay")
			elseif v == "kick" then
				launch(Vector3.new(9, MicroStage.GOAL_V - 3, 0.5), 5, 0.5, 0, "stay")
			end
			ctx.shake()
			ctx.lose()
		end
	end
	goPad(ctx, "Go!")
	local function animate(t: number)
		now = t
		local th = thing
		if th then
			local p = home
			local tilt = CFrame.identity
			local f = fly
			if f then
				local k = (t - f.t0) / f.dur
				if k < 1 then
					local base = f.from:Lerp(f.to, k)
					p = base + Vector3.new(0, 0, 4 * f.lift * k * (1 - k))
					tilt = CFrame.Angles(f.turns * 2 * math.pi * k, 0, 0)
				elseif f.mode == "back" and k < 2.4 then
					p = f.to -- in the net a moment, then back on the spot
				elseif f.mode == "stay" then
					p = f.to
				else
					fly = nil
				end
			end
			st.place(th, p.X, p.Y, p.Z, FACE, tilt)
		end
		local sl = slime
		if sl and sl.model.Parent then
			-- it bounces: squash and stretch; a hit knocks it back
			local b = math.abs(math.sin(t * 5))
			local hitK = math.clamp(1 - (t - slimeHit) / 0.25, 0, 1)
			if t < slimeHit then
				hitK = 0
			end
			local s = if ctx.tiny then 0.6 else 1
			MicroModels.scale(sl, Vector3.new(1 + 0.15 * (1 - b) + 0.2 * hitK, 1 - 0.15 * (1 - b) - 0.2 * hitK, 1 + 0.15 * (1 - b)) * s)
			st.place(sl, SLIME_U + hitK * 1.5, SLIME_V, b * 0.8 * (1 - hitK), LEFT)
		end
		if v == "strike" then
			local dk = (t - dashT) / 0.3
			m.u = if dk >= 0 and dk < 1 then -6 + 7.5 * math.sin(dk * math.pi) else -6
		end
		local swinging = t < swingUntil
		m.action = if swinging then "swing" elseif v == "flip" then "reach" else "stand"
		m.k = math.clamp(1 - (swingUntil - t) / 0.25, 0, 1)
		pose(ctx, m, t)
	end
	return {
		update = function(t: number, dt: number)
			animate(t)
			if done then
				return
			end
			pos += dir * speed * dt
			if pos >= bw - 2 then
				pos, dir = bw - 2, -1
			elseif pos <= 0 then
				pos, dir = 0, 1
			end
			needle.Position = UDim2.fromOffset(bx + math.floor(pos) - 1, by - 3)
		end,
		key = function(_k: string)
			press()
		end,
		after = function(t: number, won: boolean)
			animate(t)
			ending(ctx, m, t, won)
		end,
		auto = function()
			if pos >= zx + 1 and pos <= zx + zoneW - 1 then
				press()
			end
		end,
	}
end

------------------------------------------------------------------ 3. mash (Animals "Pet!")
function Games.mash(ctx: Ctx): Micro
	local st = ctx.stage
	local need = 8 + 2 * ctx.diff
	local n = 0
	local m = newMe(-2.75, 2.5, RIGHT)
	local cat = target(ctx, "cat", nil, 1.6)
	local catU, catV = 1.25, 2.5
	local petBox = hitbox(ctx, "Pad_go", 48, 44)
	petBox.Activated:Connect(function()
		ctx.press("go")
	end)
	local setBar = meter(ctx.area, math.floor(ctx.w / 2 - 54), 40, 120, 6, "pink", 10)
	setBar(0)
	PixelSprites.image(ctx.area, "heart", UDim2.fromOffset(math.floor(ctx.w / 2 - 54) - 14, 37), 10)
	local label = say(ctx, string.format("Pet it! 0/%d", need))
	local done = false
	local now = 0
	local petUntil = 0
	local squashUntil = 0
	local function press()
		if done then
			return
		end
		n += 1
		setBar(n / need)
		UIKit.setText(label, string.format("Pet it! %d/%d", n, need))
		Audio.play("pop", { volume = 0.6, pitch = 1 + (n % 5) * 0.06 })
		petUntil = now + 0.3
		squashUntil = now + 0.09
		local x, y = screenAt(ctx, st.at(catU, catV, cat.h + 0.5))
		local heart = PixelSprites.image(ctx.area, "heart", UDim2.fromOffset(x - 5 + ctx.rng:int(-8, 8), y - 6), 13)
		ctx.float(heart, (ctx.rng:next() - 0.5) * 16, -30, 0.7)
		ctx.burst(x, y, { "pink", "white" }, 4)
		st.puff(st.at(catU, catV, cat.h), "twinkle", 2, "pink")
		if n >= need then
			done = true
			ctx.burst(x, y + 10, { "pink", "white", "berry_red" }, 18)
			ctx.win()
		end
	end
	local function animate(t: number)
		now = t
		local breath = 1 + 0.04 * math.sin(t * 4)
		local sq = if t < squashUntil then 0.85 else 1
		local s = if ctx.tiny then 0.6 else 1
		MicroModels.scale(cat, Vector3.new(1 / math.sqrt(sq), breath * sq, 1 / math.sqrt(sq)) * s)
		st.place(cat, catU, catV, 0, yawTo(-1, 0.4))
		m.action = if t < petUntil or done then "pet" else "stand"
		m.k = 1
		pose(ctx, m, t)
		follow(ctx, petBox, st.at(catU, catV, 1.2))
	end
	return {
		update = function(t: number, _dt: number)
			animate(t)
		end,
		key = function(_k: string)
			press()
		end,
		after = function(t: number, won: boolean)
			animate(t)
			if not won then
				ending(ctx, m, t, won)
			end
		end,
		auto = function()
			press()
		end,
	}
end

------------------------------------------------------------------ 4. whack (Space "Shoot!", Farming "Water!", Zombies "Whack!")
-- Things rise out of the holes dug in the stage's floor: tap the right ones (not the decoys).
type Hole = { b: TextButton, u: number, v: number, t: Thing, d: Thing?, state: string, since: number, untilT: number, which: Thing?, bloom: Thing? }
function Games.whack(ctx: Ctx): Micro
	local st = ctx.stage
	local cols = if ctx.diff >= 3 then 4 else 3
	local rows = if ctx.diff >= 6 then 3 else 2
	local need = 4 + ctx.diff
	local v = ctx.variant
	local targetKind = if v == "space" then "alien" elseif v == "water" then "sprout" else "zombie"
	local decoyKind: string? = if v == "space" then "rocket" elseif v == "zombie" then "kid" else nil
	local colors = if v == "space" then { "green", "white", "yellow" } elseif v == "water" then { "blue", "white" } else { "green", "leaf", "white" }
	local m = newMe(10, 6, LEFT)
	st.hold(if v == "space" then "blaster" elseif v == "water" then "can" else "hammer")
	local holes: { Hole } = {}
	local hits = 0
	local now = 0
	local nextAt = 0.2
	local life = math.max(0.45, 1.05 - 0.07 * ctx.diff) / ctx.speed
	local every = math.max(0.25, 0.6 - 0.04 * ctx.diff) / ctx.speed
	local done = false
	local swingUntil = 0
	local beam: Thing? = nil
	local beamUntil, beamTo = 0, Vector3.zero
	if v == "space" then
		beam = st.adopt(MicroModels.slab(Vector3.new(0.25, 0.25, 1), "screen_code", nil, true))
	end
	local verb = if v == "water" then "Water the dry ones:" elseif v == "space" then "Shoot the aliens:" else "Whack the zombies:"
	local label = say(ctx, string.format("%s 0/%d", verb, need))
	local hit: (idx: number) -> ()
	local i = 0
	for c = 1, cols do
		for r = 4 - rows, 3 do
			i += 1
			local idx = i
			local b = hitbox(ctx, "Hole_" .. idx, 30, 30)
			local t = target(ctx, targetKind)
			MicroModels.show(t, false)
			local d = if decoyKind then target(ctx, decoyKind) else nil
			if d then
				MicroModels.show(d, false)
			end
			b.Activated:Connect(function()
				hit(idx)
			end)
			holes[idx] = { b = b, u = MicroStage.HOLE_U[c], v = MicroStage.HOLE_V[r], t = t, d = d, state = "down", since = 0, untilT = 0, which = nil, bloom = nil }
		end
	end
	hit = function(idx: number)
		local hole = holes[idx]
		if done or (hole.state ~= "rising" and hole.state ~= "up") then
			return
		end
		local p = hole.which :: Thing
		local at = st.at(hole.u, hole.v, p.h * 0.6)
		swingUntil = now + 0.2
		if beam then
			beamUntil = now + 0.09
			beamTo = at
		end
		if p == hole.d then
			done = true
			st.flash(p, 0.3)
			ctx.shake()
			burstAt(ctx, at, { "bad", "white" }, 10)
			popAt(ctx, st.at(hole.u, hole.v, p.h + 0.5), "Oops!", "bad")
			ctx.lose()
			return
		end
		hits += 1
		Audio.play("squish")
		st.flash(p, 0.12)
		burstAt(ctx, at, colors, 10)
		if v == "water" then
			st.puff(at + Vector3.new(0, 1, 0), "splash", 10)
		else
			st.puff(at, "debris", 9, if v == "space" then "green" else "leaf_dark")
			st.puff(at, "spark", 5)
		end
		popAt(ctx, st.at(hole.u, hole.v, p.h + 0.5), "+1", "good")
		UIKit.setText(label, string.format("%s %d/%d", verb, hits, need))
		if v == "water" then
			-- the sprout blooms a moment, then sinks
			MicroModels.show(p, false)
			local fl = target(ctx, "flower")
			st.place(fl, hole.u, hole.v, 0, FACE)
			st.puff(st.at(hole.u, hole.v, 2.2), "confetti", 8)
			hole.bloom = fl
			hole.state = "bloom"
			hole.since = now
		else
			hole.state = "sinking"
			hole.since = now + 0.1
		end
		if hits >= need then
			done = true
			ctx.win()
		end
	end
	local function animate(t: number)
		now = t
		for _, hole in holes do
			local p = hole.which
			local k = 0
			if hole.state == "rising" then
				k = math.clamp((t - hole.since) / 0.12, 0, 1)
				if k >= 1 then
					hole.state = "up"
				end
			elseif hole.state == "up" then
				k = 1
			elseif hole.state == "sinking" then
				k = 1 - math.clamp((t - hole.since) / 0.12, 0, 1)
				if t - hole.since >= 0.12 then
					hole.state = "down"
					hole.which = nil
				end
			elseif hole.state == "bloom" and t - hole.since > 0.4 then
				local fl = hole.bloom
				if fl then
					st.remove(fl)
				end
				hole.bloom = nil
				hole.state = "down"
				hole.which = nil
			end
			local list: { Thing } = { hole.t }
			if hole.d then
				table.insert(list, hole.d :: Thing)
			end
			for _, th in list do
				local on = th == p and k > 0 and hole.state ~= "bloom"
				MicroModels.show(th, on)
				if on then
					local wob = if th.kind == "alien" or th.kind == "zombie" then math.sin(t * 9 + hole.u) * 0.12 else 0
					st.place(th, hole.u, hole.v, -(th.h + 0.3) * (1 - k), FACE, CFrame.Angles(0, 0, wob))
				end
			end
			follow(ctx, hole.b, st.at(hole.u, hole.v, 1))
		end
		m.action = if t < swingUntil then "swing" else "stand"
		m.k = math.clamp(1 - (swingUntil - t) / 0.2, 0, 1)
		pose(ctx, m, t)
		local bm = beam
		if bm then
			local on = t < beamUntil
			MicroModels.show(bm, on)
			local hand = st.avatar.rig.parts.HandR
			if on and hand then
				local from = hand.Position
				local len = (beamTo - from).Magnitude
				if len > 0.1 then
					MicroModels.scale(bm, Vector3.new(1, 1, len))
					MicroModels.place(bm, CFrame.lookAt((from + beamTo) / 2, beamTo) * CFrame.new(0, -0.125, 0))
				end
			end
		end
	end
	return {
		update = function(t: number, _dt: number)
			for _, hole in holes do
				if (hole.state == "rising" or hole.state == "up") and t >= hole.untilT then
					hole.state = "sinking"
					hole.since = t
				end
			end
			if t >= nextAt and not done then
				nextAt = t + every
				local free = {}
				for idx, hole in holes do
					if hole.state == "down" then
						table.insert(free, idx)
					end
				end
				if #free > 0 then
					local hole = holes[free[ctx.rng:int(1, #free)]]
					local decoy = hole.d ~= nil and ctx.diff >= 4 and ctx.rng:chance(0.25)
					hole.which = if decoy and hole.d then hole.d else hole.t
					st.puff(st.at(hole.u, hole.v, 0.4), "dust", 4, if v == "space" then "purple" else "wood")
					hole.state = "rising"
					hole.since = t
					hole.untilT = t + life
				end
			end
			animate(t)
		end,
		key = function(_k: string) end,
		after = function(t: number, won: boolean)
			animate(t)
			ending(ctx, m, t, won)
		end,
		auto = function()
			for idx, hole in holes do
				if (hole.state == "rising" or hole.state == "up") and hole.which == hole.t then
					hit(idx)
					return
				end
			end
		end,
	}
end

------------------------------------------------------------------ 5. pick (Puzzle "Match!", School "Answer!", Strategy "Count!", Detectives "Spot it!")
local SHAPE_COLORS = { "berry_red", "blue", "yellow", "green", "purple", "orange" }
type Bobber = { t: Thing, u: number, v: number, y: number, ph: number }
type Walker = { t: Thing, u: number, v: number, du: number, dv: number }
function Games.pick(ctx: Ctx): Micro
	local st = ctx.stage
	local variant = ctx.variant
	local n = if ctx.diff >= 7 then 6 elseif ctx.diff >= 5 then 5 elseif ctx.diff >= 3 then 4 else 3
	local right = 1
	local done = false
	local m = newMe(0, 5, FACE)
	local mark: (i: number, good: boolean) -> () = function(_i: number, _good: boolean) end
	local where: (i: number) -> (number, number) = function(_i: number): (number, number)
		return ctx.w / 2, ctx.h / 2
	end
	local function choose(i: number)
		if done then
			return
		end
		done = true
		local x, y = where(i)
		if i == right then
			Audio.play("ding")
			mark(i, true)
			ctx.burst(x, y, { "good", "white", "yellow" }, 14)
			ctx.win()
		else
			mark(i, false)
			mark(right, true)
			ctx.burst(x, y, { "bad", "white" }, 8)
			ctx.shake()
			ctx.lose()
		end
	end
	local walkers: { Walker } = {}
	local bobbers: { Bobber } = {}
	local extra: ((t: number) -> ())? = nil
	if variant == "spot" then
		-- suspects in rows on the office floor, one in another coat: tap them
		local cols = if ctx.diff >= 6 then 6 elseif ctx.diff >= 3 then 5 else 4
		local rows = if ctx.diff >= 6 then 3 else 2
		right = ctx.rng:int(1, cols * rows)
		local coat = ({ "wood", "blue", "green", "steel_dark" })[ctx.rng:int(1, 4)]
		local odd = ({ "berry_red", "purple", "orange", "yellow" })[ctx.rng:int(1, 4)]
		type Cell = { u: number, v: number, b: TextButton, t: Thing }
		local cells: { Cell } = {}
		for i = 1, cols * rows do
			local c, r = (i - 1) % cols, (i - 1) // cols
			local u = (c - (cols - 1) / 2) * 3.2
			local vv = -2 + r * 3.5
			local t = target(ctx, "suspect", { color = if i == right then odd else coat }, 0.8)
			local b = hitbox(ctx, "Opt_" .. i, 22, 30)
			b.Activated:Connect(function()
				choose(i)
			end)
			cells[i] = { u = u, v = vv, b = b, t = t }
			table.insert(bobbers, { t = t, u = u, v = vv, y = 0, ph = i * 0.7 })
		end
		m = newMe(-11, 6, RIGHT)
		mark = function(i: number, good: boolean)
			st.flash(cells[i].t, if good then 0.6 else 0.3)
		end
		where = function(i: number): (number, number)
			return screenAt(ctx, st.at(cells[i].u, cells[i].v, 1.5))
		end
		extra = function(_t: number)
			for _, c in cells do
				follow(ctx, c.b, st.at(c.u, c.v, 1.3))
			end
		end
		say(ctx, "Spot the odd one out!")
	else
		-- a question; n options along the bottom (keys 1..n)
		local labels: { string } = {}
		if variant == "match" then
			-- shapes on pedestals: which one is the shape floating over the founder?
			right = ctx.rng:int(1, n)
			local pool = table.clone(MicroModels.SHAPES)
			for i = #pool, 2, -1 do
				local j = ctx.rng:int(1, i)
				pool[i], pool[j] = pool[j], pool[i]
			end
			local hues = table.clone(SHAPE_COLORS)
			for i = #hues, 2, -1 do
				local j = ctx.rng:int(1, i)
				hues[i], hues[j] = hues[j], hues[i]
			end
			local spec: { { shape: string, color: string } } = {}
			for i = 1, n do
				local shape, color = pool[(i - 1) % #pool + 1], hues[(i - 1) % #hues + 1]
				-- from difficulty 5 some options share the right one's shape (only the colour tells)
				if ctx.diff >= 5 and i ~= right and i % 2 == 0 then
					shape = pool[(right - 1) % #pool + 1]
				end
				spec[i] = { shape = shape, color = color }
			end
			local pedU: { number } = {}
			for i = 1, n do
				local u = (i - (n + 1) / 2) * 3.6
				local p = st.spawn("pedestal", nil, 1.1)
				st.place(p, u, 3, 0, FACE)
				local s = target(ctx, "shape", { alt = spec[i].shape, color = spec[i].color })
				table.insert(bobbers, { t = s, u = u, v = 3, y = 1.3, ph = i })
				pedU[i] = u
				labels[i] = tostring(i)
			end
			local wanted = st.spawn("shape", { alt = spec[right].shape, color = spec[right].color }, 1)
			table.insert(bobbers, { t = wanted, u = 0, v = -5, y = 5.5, ph = 0 })
			m = newMe(0, -5, FACE)
			m.action = "cast"
			where = function(i: number): (number, number)
				return screenAt(ctx, st.at(pedU[i], 3, 2))
			end
			mark = function(i: number, good: boolean)
				local b = bobbers[i]
				if b then
					st.flash(b.t, if good then 0.6 else 0.3)
				end
			end
			say(ctx, "Which one matches?")
		else
			local answer: number
			local q: string
			if variant == "answer" then
				local a, b = ctx.rng:int(1, 4 + 2 * ctx.diff), ctx.rng:int(1, 4 + 2 * ctx.diff)
				if ctx.diff >= 5 then
					a, b = ctx.rng:int(2, 3 + ctx.diff), ctx.rng:int(2, 9)
					answer, q = a * b, string.format("%d x %d = ?", a, b)
				elseif ctx.diff >= 3 and a > b then
					answer, q = a - b, string.format("%d - %d = ?", a, b)
				else
					answer, q = a + b, string.format("%d + %d = ?", a, b)
				end
				-- chalk on the board: over the board's middle on screen
				local bu, bv = uvOf(0, -12)
				local qx, qy = screenAt(ctx, st.at(bu, bv, 4.25))
				UIKit.text(ctx.area, q, UDim2.fromOffset(160, 18), UDim2.fromOffset(qx - 80, qy - 9), { x = "center", face = "big", color = WHITE, z = 10, name = "Question" })
				m = newMe(1, 5, AWAY)
			else
				-- count: toy soldiers spread over the map, never on top of each other (marching from difficulty 5)
				answer = ctx.rng:int(3, 5 + ctx.diff)
				q = "How many soldiers?"
				local cells: { number } = {}
				local gc, gr = 7, 4
				for i = 1, gc * gr do
					cells[i] = i
				end
				for i = #cells, 2, -1 do
					local j = ctx.rng:int(1, i)
					cells[i], cells[j] = cells[j], cells[i]
				end
				answer = math.min(answer, #cells)
				for k = 1, answer do
					local c, r = (cells[k] - 1) % gc, (cells[k] - 1) // gc
					local u = (c - (gc - 1) / 2) * 3 + ctx.rng:int(-4, 4) / 10
					local vv = -4 + r * 2.8 + ctx.rng:int(-3, 3) / 10
					local s = target(ctx, "soldier", nil, 0.6)
					if ctx.diff >= 5 then
						local a = ctx.rng:next() * math.pi * 2
						table.insert(walkers, { t = s, u = u, v = vv, du = math.cos(a) * 1.6, dv = math.sin(a) * 1.2 })
					else
						table.insert(bobbers, { t = s, u = u, v = vv, y = 0, ph = k })
					end
				end
				m = newMe(-11, 7, RIGHT)
			end
			say(ctx, if variant == "answer" then "Answer it!" else q)
			right = ctx.rng:int(1, n)
			for i = 1, n do
				labels[i] = tostring(math.max(0, answer + (i - right) * (if variant == "count" then 1 else ctx.rng:int(1, 3))))
			end
			for i = 1, n do
				for j = 1, i - 1 do
					if labels[i] == labels[j] then
						labels[i] = tostring(tonumber(labels[i]) :: number + 10 + i)
					end
				end
			end
		end
		local ow = math.min(36, math.floor((ctx.w - 8) / n) - 4)
		local oh = 18
		local total = n * (ow + 4) - 4
		local buttons: { TextButton } = {}
		for i = 1, n do
			local b = UIKit.button(ctx.area, labels[i] or "", UDim2.fromOffset(ow, oh), UDim2.fromOffset(math.floor((ctx.w - total) / 2) + (i - 1) * (ow + 4), ctx.h - PAD_Y - oh), function()
				choose(i)
			end, { name = "Opt_" .. i, color = UIKit.color("plate_light"), face = "big" })
			b.ZIndex = 10
			buttons[i] = b
		end
		local markStage = mark
		mark = function(i: number, good: boolean)
			UIKit.setButtonColor(buttons[i], UIKit.color(if good then "good" else "bad"))
			markStage(i, good)
		end
		if variant ~= "match" then
			where = function(i: number): (number, number)
				local b = buttons[i]
				return b.Position.X.Offset + ow / 2, b.Position.Y.Offset + oh / 2
			end
		end
	end
	local function animate(t: number, dt: number)
		for _, w in walkers do
			w.u += w.du * dt * ctx.speed
			w.v += w.dv * dt * ctx.speed
			if math.abs(w.u) > 9 then
				w.du = -w.du
				w.u = math.clamp(w.u, -9, 9)
			end
			if w.v < -5 or w.v > 5 then
				w.dv = -w.dv
				w.v = math.clamp(w.v, -5, 5)
			end
			st.place(w.t, w.u, w.v, if math.floor(t * 8 + w.u) % 2 == 0 then 0.15 else 0, yawTo(w.du, w.dv))
		end
		for _, b in bobbers do
			st.place(b.t, b.u, b.v, b.y + (if math.floor(t * 3 + b.ph) % 4 == 0 then 0.25 else 0), FACE)
		end
		if extra then
			extra(t)
		end
		pose(ctx, m, t)
	end
	return {
		update = function(t: number, dt: number)
			animate(t, dt)
		end,
		key = function(k: string)
			local i = tonumber(k)
			if i and i >= 1 and i <= n then
				choose(i)
			end
		end,
		after = function(t: number, won: boolean)
			animate(t, 0)
			ending(ctx, m, t, won)
		end,
		auto = function()
			choose(right)
		end,
	}
end

------------------------------------------------------------------ 6. sequence (Fantasy "Cast!", Robots "Program!", Music "Repeat!")
local DIRS = { "up", "right", "down", "left" }
local STEP: { [string]: Vector2 } = { up = Vector2.new(0, -1), right = Vector2.new(1, 0), down = Vector2.new(0, 1), left = Vector2.new(-1, 0) }
function Games.sequence(ctx: Ctx): Micro
	local st = ctx.stage
	if ctx.variant == "simon" then
		-- four coloured pads light up a tune; play it back: the founder hops onto each pad
		local len = 2 + math.floor(ctx.diff / 2)
		local seq: { number } = {}
		for i = 1, len do
			seq[i] = ctx.rng:int(1, 4)
		end
		local colors = { "berry_red", "yellow", "blue", "green" }
		local uiColors = { "fun", "ideas", "graphics", "sound" }
		local pads: { Thing } = {}
		local padU: { number } = {}
		local PAD_V = 2.5
		local m = newMe(0, -2, FACE)
		for i = 1, 4 do
			padU[i] = (i - 2.5) * 3.75
			local p = st.spawn("pad", { color = colors[i] })
			st.place(p, padU[i], PAD_V, 0, 0)
			pads[i] = p
		end
		local pw = 36
		local total = 4 * (pw + 4) - 4
		for i = 1, 4 do
			local b = pad(ctx, tostring(i), tostring(i), (ctx.w - total) / 2 + (i - 1) * (pw + 4), ctx.h - PAD_Y - 16, pw, 16, "plate_light")
			UIKit.setButtonColor(b, UIKit.color(uiColors[i]))
		end
		local label = say(ctx, "Watch...")
		local step = 0.5 / ctx.speed
		local showing = true
		local at = 1
		local done = false
		local lit = 0
		local hopFrom, hopTo, hopT = Vector2.new(0, -2), Vector2.new(0, -2), -10
		local now = 0
		local function light(i: number, on: boolean)
			st.glow(pads[i], on)
			if on then
				local x, y = screenAt(ctx, st.at(padU[i], PAD_V, 1))
				local note = PixelSprites.image(ctx.area, "note", UDim2.fromOffset(x - 5, y - 10), 13)
				ctx.float(note, (ctx.rng:next() - 0.5) * 14, -32, 0.6)
				ctx.burst(x, y, { uiColors[i], "white" }, 5)
			end
		end
		local function press(i: number)
			if showing or done then
				return
			end
			light(i, true)
			hopFrom, hopTo, hopT = Vector2.new(m.u, m.v), Vector2.new(padU[i], PAD_V), now
			task.delay(0.18, function()
				st.puff(st.at(padU[i], PAD_V, 0.6), "spark", 8, colors[i])
			end)
			task.delay(0.18, function()
				if pads[i].model.Parent then
					light(i, false)
				end
			end)
			Audio.play("tick", { pitch = 0.8 + i * 0.15 })
			if i == seq[at] then
				at += 1
				if at > len then
					done = true
					ctx.win()
				end
			else
				done = true
				ctx.shake()
				ctx.lose()
			end
		end
		local function animate(t: number)
			now = t
			local k = math.clamp((t - hopT) / 0.18, 0, 1)
			m.u = hopFrom.X + (hopTo.X - hopFrom.X) * k
			m.v = hopFrom.Y + (hopTo.Y - hopFrom.Y) * k
			local onPad = hopT > 0
			m.y = (if onPad then 0.5 else 0) + 1.6 * math.sin(k * math.pi)
			m.action = if k < 1 then "jump" elseif showing then "stand" else "dance"
			pose(ctx, m, t)
		end
		return {
			clock = 1.6,
			update = function(t: number, _dt: number)
				animate(t)
				if not showing then
					return
				end
				local k = math.floor(t / step) + 1
				local phase = (t / step) % 1
				if k > len then
					showing = false
					if lit > 0 then
						light(lit, false)
					end
					UIKit.setText(label, "Your turn: repeat it!")
					return
				end
				local want = if phase < 0.7 then seq[k] else 0
				if want ~= lit then
					if lit > 0 then
						light(lit, false)
					end
					if want > 0 then
						light(want, true)
						Audio.play("tick", { pitch = 0.8 + want * 0.15 })
					end
					lit = want
				end
			end,
			key = function(kk: string)
				local i = tonumber(kk) or table.find(DIRS, kk)
				if i then
					press(i)
				end
			end,
			after = function(t: number, won: boolean)
				animate(t)
				ending(ctx, m, t, won)
			end,
			auto = function()
				if not showing then
					press(seq[at])
				end
			end,
		}
	end
	-- a row of arrows to type in order (Robots from difficulty 4: they hide after a look)
	local program = ctx.variant == "program"
	local len = 3 + math.floor(ctx.diff / 2)
	local seq: { string } = {}
	for i = 1, len do
		seq[i] = DIRS[ctx.rng:int(1, 4)]
	end
	local suffix = if ctx.tiny then "_t" else ""
	local aw = if ctx.tiny then 7 else 13
	local tw = math.min(aw + 6, math.floor((ctx.w - 10) / len) - 3)
	local total = len * (tw + 3) - 3
	local tx0, ty = math.floor((ctx.w - total) / 2), 38
	type Tile = { p: Frame, a: GuiObject, x: number }
	local tiles: { Tile } = {}
	for i = 1, len do
		local x = tx0 + (i - 1) * (tw + 3)
		local p = UIKit.plate(ctx.area, UDim2.fromOffset(tw, tw), UDim2.fromOffset(x, ty), UIKit.color("plate_light"), 0, 2)
		p.ZIndex = 8
		local a = PixelSprites.image(p, "arrow_" .. seq[i] .. suffix, UDim2.fromOffset(math.floor((tw - aw) / 2), math.floor((tw - aw) / 2)), 9)
		tiles[i] = { p = p, a = a, x = x }
	end
	-- the stage: the founder walks the board to the flag (Robots), or casts at the orb over their head (Fantasy)
	local bd = MicroStage.BOARD
	local cell = Vector2.new(math.ceil(bd.cols / 2), math.ceil(bd.rows / 2))
	local function cellUV(c: Vector2): (number, number)
		return (c.X - (bd.cols + 1) / 2) * bd.step, bd.v0 + (c.Y - (bd.rows + 1) / 2) * bd.step
	end
	local m = newMe(0, 2, FACE)
	local walkFrom, walkTo, walkT = Vector2.zero, Vector2.zero, -10
	local orb: Thing? = nil
	local castUntil = 0
	if program then
		local goal = cell
		for _, d in seq do
			local nx = goal + STEP[d]
			goal = Vector2.new(math.clamp(nx.X, 1, bd.cols), math.clamp(nx.Y, 1, bd.rows))
		end
		local flag = st.spawn("flag", nil, 0.6)
		local gu, gv = cellUV(goal)
		st.place(flag, gu + 0.7, gv - 0.7, 0.25, FACE)
		local u, vv = cellUV(cell)
		m = newMe(u, vv, FACE)
		m.y = 0.25
		walkFrom, walkTo = Vector2.new(u, vv), Vector2.new(u, vv)
	else
		st.hat("hat")
		orb = st.spawn("orb", nil, 0.5)
	end
	local hideAt = if program and ctx.diff >= 4 then 1.2 / ctx.speed else math.huge
	local hidden = false
	local at = 1
	local done = false
	local now = 0
	local level = 0
	say(ctx, if program then "Walk the arrows to the flag!" else "Cast the spell!")
	local function highlight()
		for i, tl in ipairs(tiles) do
			UIKit.setPlate(tl.p, if i < at then UIKit.color("good") elseif i == at then UIKit.color("button") else UIKit.color("plate_light"))
		end
	end
	highlight()
	arrowPads(ctx, { "left", "up", "down", "right" })
	local function typeKey(k: string)
		if done or table.find(DIRS, k) == nil then
			return
		end
		local tl = tiles[at]
		if k == seq[at] then
			tl.a.Visible = true
			Audio.play("key")
			ctx.burst(tl.x + tw / 2, ty + tw / 2, if program then { "good", "white" } else { "purple", "yellow", "white" }, 5)
			tl.p.Position = UDim2.fromOffset(tl.x, ty - 2)
			UIKit.tween(tl.p, 0.1, { Position = UDim2.fromOffset(tl.x, ty) })
			if program then
				local nx = cell + STEP[k]
				cell = Vector2.new(math.clamp(nx.X, 1, bd.cols), math.clamp(nx.Y, 1, bd.rows))
				local u, vv = cellUV(cell)
				walkFrom, walkTo, walkT = Vector2.new(m.u, m.v), Vector2.new(u, vv), now
				task.delay(0.14, function()
					st.puff(st.at(u, vv, 0.4), "dust", 4)
				end)
			else
				level += 1
				castUntil = now + 0.3
				burstAt(ctx, st.at(m.u, m.v, 5.5 + level * 0.2), { "purple", "yellow", "white" }, 6)
				st.puff(st.at(m.u, m.v, 5.3), "twinkle", 6, "purple")
			end
			at += 1
			highlight()
			if at > len then
				done = true
				burstAt(ctx, st.at(m.u, m.v, 3), if program then { "yellow", "white", "good" } else { "purple", "yellow", "white", "pink" }, 20)
				ctx.win()
			end
		else
			done = true
			UIKit.setPlate(tl.p, UIKit.color("bad"))
			tl.a.Visible = true
			ctx.shake()
			ctx.lose()
		end
	end
	local function animate(t: number)
		now = t
		if program then
			local k = math.clamp((t - walkT) / 0.14, 0, 1)
			m.u = walkFrom.X + (walkTo.X - walkFrom.X) * k
			m.v = walkFrom.Y + (walkTo.Y - walkFrom.Y) * k
			m.y = 0.25 + 0.8 * math.sin(k * math.pi)
			m.speed = if k < 1 then 14 else 0
			local d = walkTo - walkFrom
			if d.Magnitude > 0.1 then
				m.yaw = yawTo(d.X, d.Y)
			end
			m.action = "stand"
		else
			m.action = if t < castUntil then "cast" else "stand"
			local ob = orb
			if ob and ob.model.Parent then
				MicroModels.scale(ob, Vector3.one * (0.6 + 0.25 * level))
				st.place(ob, m.u, m.v, 5.2 + math.sin(t * 4) * 0.2, 0)
			end
		end
		pose(ctx, m, t)
	end
	return {
		update = function(t: number, _dt: number)
			animate(t)
			if not hidden and t >= hideAt then
				hidden = true
				for i, tl in tiles do
					if i >= at then
						tl.a.Visible = false
					end
				end
			end
		end,
		key = typeKey,
		after = function(t: number, won: boolean)
			animate(t)
			ending(ctx, m, t, won)
			local ob = orb
			if ob and won then
				st.remove(ob)
				orb = nil
			end
		end,
		auto = function()
			if seq[at] then
				typeKey(seq[at])
			end
		end,
	}
end

------------------------------------------------------------------ 7. catch (Pirates "Loot!", Ocean "Catch!")
function Games.catch(ctx: Ctx): Micro
	local st = ctx.stage
	local fish = ctx.variant == "fish"
	local n = if ctx.diff >= 5 then 5 else 4
	local row = 2.5
	local m = newMe(0, row, FACE)
	local L = lanes(ctx, n, row, m)
	st.hat("basket")
	local goodKind = if fish then "fish" else "coin"
	local badKind = if fish then "jelly" else "bomb"
	local need = 3 + math.floor(ctx.diff / 2)
	local got = 0
	local items: { Fall } = {}
	local nextAt = 0.3
	local fall = (7 + 1.4 * ctx.diff) * ctx.speed
	local every = math.max(0.3, 0.7 - 0.05 * ctx.diff) / ctx.speed
	local badShare = math.min(0.5, 0.2 + 0.04 * ctx.diff)
	local done = false
	local TOP = 16
	local CATCH = 5.0 -- the basket's rim over the floor
	local bumpUntil = 0
	local verb = if fish then "Catch fish, not jellies:" else "Grab coins, not bombs:"
	local label = say(ctx, string.format("%s 0/%d", verb, need))
	local function animate(t: number, dt: number)
		local moving = L.step(dt)
		m.speed = if moving then 14 else 0
		m.y = if t < bumpUntil then -0.15 else 0
		m.action = "cheer"
		pose(ctx, m, t)
	end
	return {
		update = function(t: number, dt: number)
			animate(t, dt)
			if done then
				return
			end
			if t >= nextAt then
				nextAt = t + every * (0.7 + 0.6 * ctx.rng:next())
				local l = ctx.rng:int(1, n)
				local good = not ctx.rng:chance(badShare)
				local th = target(ctx, if good then goodKind else badKind, nil, 1)
				table.insert(items, { t = th, lane = l, y = TOP, v = row, gone = false, good = good, spin = ctx.rng:next() * 6 })
			end
			for _, it in items do
				if not it.gone then
					it.y -= fall * dt
					local yaw = if it.good and not fish then (t * 6 + it.spin) elseif fish then FACE + math.sin(t * 10 + it.spin) * 0.35 else FACE
					st.place(it.t, L.u(it.lane), row, math.max(0, it.y), yaw)
					local spark = it.t.parts.Spark
					if spark then
						spark.Transparency = if math.floor(t * 12) % 2 == 0 then 0 else 1
					end
					if it.lane == L.lane() and it.y < CATCH and it.y > CATCH - 1.5 then
						it.gone = true
						st.remove(it.t)
						local p = st.at(m.u, row, CATCH)
						if it.good then
							got += 1
							Audio.play("coin")
							bumpUntil = t + 0.08
							burstAt(ctx, p, if fish then { "orange", "white", "blue" } else { "yellow", "white", "gold" }, 9)
							st.puff(p, if fish then "splash" else "spark", 8)
							popAt(ctx, p, "+1", "accent")
							UIKit.setText(label, string.format("%s %d/%d", verb, got, need))
							if got >= need then
								done = true
								ctx.win()
								return
							end
						else
							done = true
							burstAt(ctx, p, if fish then { "pink", "white", "purple" } else { "orange", "yellow", "bad", "white" }, 20)
							st.puff(p, "debris", 12, if fish then "pink" else "black")
							st.puff(p, if fish then "splash" else "spark", 12)
							if not fish then
								ctx.flash("white")
							end
							ctx.shake()
							ctx.lose()
							return
						end
					elseif it.y <= 0 then
						it.gone = true
						burstAt(ctx, st.at(L.u(it.lane), row, 0.3), if it.good then { "yellow", "white" } else { "steel", "white" }, 5)
						st.puff(st.at(L.u(it.lane), row, 0.3), if fish then "splash" else "dust", 5)
						st.remove(it.t)
					end
				end
			end
		end,
		key = function(k: string)
			if k == "left" then
				L.move(-1)
			elseif k == "right" then
				L.move(1)
			end
		end,
		after = function(t: number, won: boolean)
			ending(ctx, m, t, won)
		end,
		auto = function()
			local function badNear(l: number): boolean
				for _, it in items do
					if not it.gone and not it.good and it.lane == l and it.y < CATCH + 4 and it.y > CATCH - 1.5 then
						return true
					end
				end
				return false
			end
			local here = L.lane()
			local best: Fall? = nil
			for _, it in items do
				if not it.gone and it.good and it.y > CATCH - 1.5 and not badNear(it.lane) and (best == nil or it.y < (best :: Fall).y) then
					best = it
				end
			end
			local tgt = if best then (best :: Fall).lane else here
			if badNear(here) and tgt == here then
				for _, d in { -1, 1, -2, 2 } do
					local l = here + d
					if l >= 1 and l <= n and not badNear(l) then
						tgt = l
						break
					end
				end
			end
			if tgt ~= here then
				local step = if tgt > here then 1 else -1
				if not badNear(here + step) or badNear(here) then
					L.move(step)
				end
			end
		end,
	}
end

------------------------------------------------------------------ 8. jump (Adventure "Leap!", Dinosaurs "Jump!")
-- The founder runs up the path (world -X, toward the screen's upper left); rocks or cacti come down it: jump them.
function Games.jump(ctx: Ctx): Micro
	local st = ctx.stage
	local dino = ctx.variant == "dino"
	local RUN_X = 5
	local u0, v0 = uvOf(RUN_X, 0)
	local m = newMe(u0, v0, math.atan2(-1, 0)) -- facing -X
	local obKind = if dino then "cactus" else "rock"
	type Ob = { t: Thing, x: number, gone: boolean }
	local obs: { Ob } = {}
	local speed = (7 + 1.1 * ctx.diff) * ctx.speed -- studs a second
	local specks = st.spawn("specks", { color = if dino then "sand_dark" else "grass_dark" })
	local nextAt = 0.6
	local jumpT = -1
	local JUMP = 0.62 / ctx.speed
	local H = if ctx.tiny then 3.6 else 4.2
	local dead = false
	local dust = if dino then { "yellow", "wood" } else { "white", "leaf" }
	goPad(ctx, "Jump!")
	say(ctx, if dino then "Jump the cacti!" else "Leap over the rocks!")
	local now = 0
	local function jump()
		if jumpT < 0 and not dead then
			jumpT = now
			Audio.play("pop", { pitch = 1.3 })
			burstAt(ctx, st.at(m.u, m.v, 0.2), dust, 5)
			st.puff(st.at(m.u, m.v, 0.2), "dust", 6)
		end
	end
	return {
		survive = true,
		update = function(t: number, dt: number)
			now = t
			if dead then
				return
			end
			if jumpT >= 0 then
				local k = (t - jumpT) / JUMP
				if k >= 1 then
					jumpT = -1
					m.y = 0
					burstAt(ctx, st.at(m.u, m.v, 0.2), dust, 6)
					st.puff(st.at(m.u, m.v, 0.2), "dust", 8)
				else
					m.y = 4 * H * k * (1 - k)
				end
			end
			m.action = if m.y > 0 then "jump" else "stand"
			m.speed = if m.y > 0 then 0 else 16
			pose(ctx, m, t)
			-- the ground runs under them
			local su, sv = uvOf((t * speed) % 4 - 2, 0)
			st.place(specks, su, sv, 0, math.pi / 2)
			if t >= nextAt then
				nextAt = t + math.max(0.55, (1.25 - 0.06 * ctx.diff)) / ctx.speed * (0.8 + 0.5 * ctx.rng:next())
				table.insert(obs, { t = target(ctx, obKind, nil, 1.2), x = -15, gone = false })
			end
			for _, o in obs do
				if not o.gone then
					o.x += speed * dt
					local ou, ov = uvOf(o.x, 0)
					st.place(o.t, ou, ov, 0, 0)
					-- the founder's body against the thing's (a little inside their outlines)
					if math.abs(o.x - RUN_X) < o.t.r * 0.6 + 0.4 and m.y < o.t.h - 0.3 then
						dead = true
						st.flash(o.t, 0.3)
						burstAt(ctx, st.at(m.u, m.v, 2), { "white", "bad", "accent" }, 14)
						st.puff(st.at(m.u, m.v, 1.5), "debris", 10, if dino then "leaf" else "steel")
						ctx.shake()
						ctx.lose()
						return
					end
					if o.x > 16 then
						o.gone = true
						st.remove(o.t)
					end
				end
			end
		end,
		key = function(k: string)
			if k == "go" or k == "up" then
				jump()
			end
		end,
		after = function(t: number, won: boolean)
			ending(ctx, m, t, won)
		end,
		auto = function()
			-- jump so the top of the arc comes as the thing goes under
			for _, o in obs do
				if not o.gone and o.x < RUN_X and RUN_X - o.x < speed * JUMP * 0.5 + 0.3 then
					jump()
					return
				end
			end
		end,
	}
end

------------------------------------------------------------------ 9. rhythm (Rhythm "Tap the beat!")
-- Gems slide down the lanes toward the pads at the front: tap each lane as its gem reaches its pad.
function Games.rhythm(ctx: Ctx): Micro
	local st = ctx.stage
	local nLanes = if ctx.diff >= 5 then 3 else 2
	local count = 6 + ctx.diff
	local beat = math.max(0.3, 0.55 - 0.025 * ctx.diff) / ctx.speed
	local travel = 1.1 / ctx.speed
	local win = math.max(0.1, 0.2 - 0.01 * ctx.diff)
	local allowed = math.max(0, 2 - math.floor(ctx.diff / 3))
	type Note = { t: number, lane: number, g: Thing?, judged: boolean }
	local notes: { Note } = {}
	local tt = 0.9
	for _ = 1, count do
		table.insert(notes, { t = tt, lane = ctx.rng:int(1, nLanes), judged = false })
		tt += beat * (if ctx.rng:chance(0.25) then 0.5 else 1)
	end
	local lastT = notes[#notes].t
	local HIT_V, FAR_V = 4, -12
	local laneColors = { "sound", "fun", "ideas" }
	local gemColors = { "pink", "yellow", "blue" }
	local padColors = { "pink", "orange", "blue" }
	local keysFor = { { "left", "1" }, { "down", "2", "go" }, { "right", "3" } }
	if nLanes == 2 then
		keysFor = { { "left", "1" }, { "right", "2", "go" } }
	end
	local laneU: { number } = {}
	local pads: { Thing } = {}
	local m = newMe(9.5, 4.5, LEFT)
	for l = 1, nLanes do
		laneU[l] = (l - (nLanes + 1) / 2) * 4
		local strip = st.spawn("lane", { color = "plastic_dark" })
		st.place(strip, laneU[l], (HIT_V + FAR_V) / 2 - 1, 0, FACE)
		local p = st.spawn("pad", { color = padColors[l] })
		MicroModels.scale(p, Vector3.new(0.8, 0.6, 0.8))
		st.place(p, laneU[l], HIT_V, 0, 0)
		pads[l] = p
	end
	local pw = 34
	local total = nLanes * (pw + 4) - 4
	for l = 1, nLanes do
		pad(ctx, tostring(l), tostring(l), (ctx.w - total) / 2 + (l - 1) * (pw + 4), ctx.h - PAD_Y - 16, pw, 16, laneColors[l])
	end
	local misses = 0
	local now = 0
	local done = false
	local danceUntil = 0
	local label = say(ctx, string.format("Tap on the pads! Misses %d/%d", 0, allowed))
	local function glow(l: number)
		st.glow(pads[l], true)
		task.delay(0.12, function()
			if pads[l].model.Parent then
				st.glow(pads[l], false)
			end
		end)
	end
	local function miss(l: number?)
		misses += 1
		UIKit.setText(label, string.format("Tap on the pads! Misses %d/%d", misses, allowed))
		if l then
			st.flash(pads[l], 0.15)
			popAt(ctx, st.at(laneU[l], HIT_V, 1), "Miss", "bad")
		end
		if misses > allowed and not done then
			done = true
			ctx.shake()
			ctx.lose()
		end
	end
	local function hit(l: number)
		if done then
			return
		end
		local best: Note? = nil
		for _, nn in notes do
			if not nn.judged and nn.lane == l and math.abs(nn.t - now) <= win and (best == nil or math.abs(nn.t - now) < math.abs((best :: Note).t - now)) then
				best = nn
			end
		end
		if best then
			local b = best :: Note
			b.judged = true
			if b.g then
				st.remove(b.g :: Thing)
				b.g = nil
			end
			Audio.play("tick", { pitch = 0.9 + l * 0.15 })
			local perfect = math.abs(b.t - now) < win / 2
			glow(l)
			danceUntil = now + 0.25
			local p = st.at(laneU[l], HIT_V, 0.8)
			burstAt(ctx, p, { laneColors[l], "white" }, if perfect then 12 else 7)
			st.puff(p, "spark", if perfect then 10 else 5, gemColors[l])
			popAt(ctx, p, if perfect then "Perfect!" else "Good", if perfect then "yellow" else "accent")
		else
			miss(l)
		end
	end
	return {
		clock = 99, -- the song decides: it ends after its last note
		update = function(t: number, _dt: number)
			now = t
			m.action = if t < danceUntil then "dance" else "stand"
			pose(ctx, m, t)
			if done then
				return
			end
			local open = false
			for _, nn in notes do
				if not nn.judged then
					open = true
					local d = nn.t - t
					if d < -win then
						nn.judged = true
						if nn.g then
							st.remove(nn.g :: Thing)
							nn.g = nil
						end
						miss(nn.lane)
					elseif d <= travel then
						if nn.g == nil then
							nn.g = target(ctx, "gem", { color = gemColors[nn.lane] }, 0.5)
						end
						st.place(nn.g :: Thing, laneU[nn.lane], HIT_V - (HIT_V - FAR_V) * (d / travel), 0.4, t * 3)
					end
				end
			end
			if not open and not done and t > lastT then
				done = true
				ctx.win()
			end
		end,
		key = function(k: string)
			for l, ks in keysFor do
				if table.find(ks, k) then
					hit(l)
					return
				end
			end
		end,
		after = function(t: number, won: boolean)
			ending(ctx, m, t, won)
		end,
		auto = function()
			for _, nn in notes do
				if not nn.judged and math.abs(nn.t - now) <= win * 0.4 then
					hit(nn.lane)
					return
				end
			end
		end,
	}
end

------------------------------------------------------------------ 10. slice (Ninjas "Slice!")
-- Fruit (and from difficulty 3 bombs) are thrown up over the dojo: tap the fruit to cut it.
type Fly = { b: TextButton, t: Thing, u: number, v: number, y: number, vu: number, vy: number, bomb: boolean, gone: boolean, spin: number }
type Half = { t: Thing, u: number, v: number, y: number, vu: number, vy: number, t0: number }
function Games.slice(ctx: Ctx): Micro
	local st = ctx.stage
	local need = 4 + math.floor(ctx.diff / 2)
	local got = 0
	local flies: { Fly } = {}
	local halves: { Half } = {}
	local nextAt = 0.2
	local every = math.max(0.3, 0.75 - 0.05 * ctx.diff) / ctx.speed
	local g = 26 * ctx.speed * ctx.speed
	local done = false
	local k = 0
	local m = newMe(-10, 6, RIGHT)
	st.hold("sword")
	local swingUntil = 0
	local now = 0
	local label = say(ctx, string.format("Slice the fruit, not the bombs! 0/%d", need))
	-- a slash: a 1 px diagonal (a clean 1:1 line, no jaggies) gone in a blink
	local function slash(x: number, y: number, len: number)
		local f = Instance.new("Frame")
		f.Name = "Slash"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromOffset(len, len)
		f.Position = UDim2.fromOffset(snap(x - len / 2), snap(y - len / 2))
		f.ZIndex = 14
		f.Active = false
		for i = 0, len - 1 do
			UIKit.rect(f, UDim2.fromOffset(1, 1), UDim2.fromOffset(i, len - 1 - i), WHITE, 14)
		end
		f.Parent = ctx.area
		ctx.float(f, 0, 0, 0.1)
	end
	local function cut(f: Fly)
		if done or f.gone then
			return
		end
		f.gone = true
		f.b:Destroy()
		swingUntil = now + 0.2
		local p = st.at(f.u, f.v, f.y + 0.9)
		local x, y = screenAt(ctx, p)
		slash(x, y, 18)
		st.remove(f.t)
		if f.bomb then
			done = true
			ctx.flash("white")
			burstAt(ctx, p, { "orange", "yellow", "bad", "white" }, 22)
			st.puff(p, "debris", 14, "black")
			st.puff(p, "spark", 14)
			st.puff(p, "smoke", 4)
			ctx.shake()
			popAt(ctx, p, "Boom!", "bad")
			ctx.lose()
			return
		end
		got += 1
		Audio.play("squish", { pitch = 1.2 })
		for _, side in { -1, 1 } do
			local h = target(ctx, "half", nil, 0.6)
			table.insert(halves, { t = h, u = f.u, v = f.v, y = f.y + 0.6, vu = f.vu + side * 4, vy = 4, t0 = now })
		end
		burstAt(ctx, p, { "berry_red", "pink", "green" }, 12)
		st.puff(p, "debris", 10, "berry_red")
		popAt(ctx, p, "Slice!", "good")
		UIKit.setText(label, string.format("Slice the fruit, not the bombs! %d/%d", got, need))
		if got >= need then
			done = true
			ctx.win()
		end
	end
	local function animate(t: number, dt: number)
		now = t
		for i = #halves, 1, -1 do
			local h = halves[i]
			h.vy -= g * dt
			h.u += h.vu * dt
			h.y += h.vy * dt
			if h.y < 0 then
				h.y, h.vy, h.vu = 0, 0, 0
			end
			st.place(h.t, h.u, h.v, h.y, FACE, CFrame.Angles((t - h.t0) * 8 * (if h.vu < 0 then -1 else 1), 0, 0))
			if t - h.t0 > 0.9 then
				st.remove(h.t)
				table.remove(halves, i)
			end
		end
		m.action = if t < swingUntil then "swing" else "stand"
		m.k = math.clamp(1 - (swingUntil - t) / 0.2, 0, 1)
		pose(ctx, m, t)
	end
	return {
		update = function(t: number, dt: number)
			animate(t, dt)
			if done then
				return
			end
			if t >= nextAt then
				nextAt = t + every * (0.7 + 0.6 * ctx.rng:next())
				k += 1
				local bomb = ctx.diff >= 3 and ctx.rng:chance(0.25)
				local b = hitbox(ctx, (if bomb then "Bomb_" else "Fruit_") .. k, 30, 30)
				local th = target(ctx, if bomb then "bomb" else "fruit", nil, 1)
				local fl: Fly = { b = b, t = th, u = ctx.rng:int(-70, 70) / 10, v = ctx.rng:int(-20, 30) / 10, y = -1, vu = (ctx.rng:next() - 0.5) * 5 * ctx.speed, vy = (12 + ctx.rng:next() * 3) * ctx.speed, bomb = bomb, gone = false, spin = ctx.rng:next() * 6 }
				b.Activated:Connect(function()
					cut(fl)
				end)
				table.insert(flies, fl)
			end
			for _, f in flies do
				if not f.gone then
					f.vy -= g * dt
					f.u += f.vu * dt
					f.y += f.vy * dt
					st.place(f.t, f.u, f.v, f.y, f.spin + t * 2)
					local spark = f.t.parts.Spark
					if spark then
						spark.Transparency = if math.floor(t * 12) % 2 == 0 then 0 else 1
					end
					follow(ctx, f.b, st.at(f.u, f.v, f.y + 0.9))
					if f.y < -2 and f.vy < 0 then
						f.gone = true
						f.b:Destroy()
						st.remove(f.t)
					end
				end
			end
		end,
		key = function(_k: string) end,
		after = function(t: number, won: boolean)
			animate(t, 1 / 60)
			ending(ctx, m, t, won)
		end,
		auto = function()
			for _, f in flies do
				if not f.gone and not f.bomb and f.y > 1 then
					cut(f)
					return
				end
			end
		end,
	}
end

------------------------------------------------------------------ 11. hide (Horror "Sneak!")
-- Sneak along the hall to the door while the ghost looks away; freeze while it watches.
local DOOR_X = 9 -- the door's middle along the right wall (room space x; the wall at z = -12)
function Games.hide(ctx: Ctx): Micro
	local st = ctx.stage
	local steps = 5 + ctx.diff
	local at = 0
	local du, dv = uvOf(DOOR_X, -12 + 1.6)
	local u0, v0 = -12, 3.5
	local function stepUV(i: number): (number, number)
		local k = i / steps
		return u0 + (du - u0) * k, v0 + (dv - v0) * k
	end
	local m = newMe(u0, v0, yawTo(du - u0, dv - v0))
	local ghost = st.spawn("ghost", nil, 1.6)
	local gu, gv = -1, -5
	local red = box(ctx.area, ctx.w, ctx.h, 0, 0, "bad", 20)
	red.Name = "Watching"
	red.BackgroundTransparency = 1
	red.Active = false
	local eyes = say(ctx, "Sneak while it looks away!")
	local state = "away" -- "away" | "warn" | "watch"
	local untilT = 0.8 + ctx.rng:next()
	local done = false
	local now = 0
	local warnT = math.max(0.25, 0.55 - 0.04 * ctx.diff) / ctx.speed
	local hopT = -10
	local function setEyes(watch: boolean)
		for _, nm in { "EyeL", "EyeR" } do
			local p = ghost.parts[nm]
			p.Color = UIKit.color(if watch then "bad" else "ink")
			p.Material = if watch then Enum.Material.Neon else Enum.Material.SmoothPlastic
		end
		st.refresh(ghost)
	end
	local function step()
		if done then
			return
		end
		if state == "watch" then
			done = true
			st.flash(ghost, 0.2)
			st.puff(st.at(gu, gv, 3), "spark", 10, "berry_red")
			ctx.shake()
			popAt(ctx, st.at(m.u, m.v, 5), "Seen!", "bad")
			ctx.lose()
			return
		end
		at += 1
		hopT = now
		Audio.play("key", { pitch = 0.8 })
		burstAt(ctx, st.at(m.u, m.v, 0.2), { "wood_dark", "text_dim" }, 3)
		st.puff(st.at(m.u, m.v, 0.2), "dust", 3)
		if at >= steps then
			done = true
			burstAt(ctx, st.at(du, dv, 3), { "yellow", "white", "good" }, 16)
			st.puff(st.at(du, dv, 3), "confetti", 16)
			ctx.win()
		end
	end
	goPad(ctx, "Step")
	local function animate(t: number)
		now = t
		local k = math.clamp((t - hopT) / 0.14, 0, 1)
		local a1u, a1v = stepUV(at)
		local a0u, a0v = stepUV(math.max(0, at - 1))
		m.u = a0u + (a1u - a0u) * k
		m.v = a0v + (a1v - a0v) * k
		m.y = 0.6 * math.sin(k * math.pi)
		m.speed = if k < 1 then 10 else 0
		m.action = "sneak"
		pose(ctx, m, t)
		-- the ghost bobs; turning, it jitters; watching, it faces the hall with red eyes
		local jig = if state == "warn" then (if math.floor(t * 30) % 2 == 0 then 0.25 else -0.25) else 0
		local yaw = if state == "watch" then FACE elseif state == "warn" then AWAY + math.sin(t * 20) * 0.4 else AWAY
		st.place(ghost, gu + jig, gv, 1 + math.sin(t * 3) * 0.3, yaw)
	end
	return {
		clock = 1.5,
		update = function(t: number, _dt: number)
			animate(t)
			if done then
				return
			end
			if t >= untilT then
				if state == "away" then
					state = "warn"
					untilT = t + warnT
					popAt(ctx, st.at(gu, gv, 6), "!", "accent")
				elseif state == "warn" then
					state = "watch"
					setEyes(true)
					untilT = t + (0.6 + 0.6 * ctx.rng:next()) / ctx.speed
				else
					state = "away"
					setEyes(false)
					untilT = t + math.max(0.4, (1.2 - 0.07 * ctx.diff + ctx.rng:next() * 0.8)) / ctx.speed
				end
				UIKit.setText(eyes, if state == "watch" then "It's watching! Freeze!" elseif state == "warn" then "It's turning..." else "Sneak while it looks away!")
				UIKit.setTextColor(eyes, if state == "watch" then UIKit.color("bad") elseif state == "warn" then UIKit.color("accent") else UIKit.color("text"))
			end
			red.BackgroundTransparency = if state == "watch" then 0.88 else 1
		end,
		key = function(k: string)
			if k == "go" or k == "right" then
				step()
			end
		end,
		after = function(t: number, won: boolean)
			animate(t)
			ending(ctx, m, t, won)
		end,
		auto = function()
			if state == "away" and untilT - now > 0.12 then
				step()
			end
		end,
	}
end

------------------------------------------------------------------ 12. stack (Simulation "Build!")
-- Floors slide on the crane's rope along one side of the tower, then the other: drop each on the one below; what
-- hangs over is cut off and falls.
local FLOOR_COLORS = { "blue", "orange", "purple", "green", "pink", "yellow", "berry_red" }
type Falling = { t: Thing, x: number, z: number, y: number, vy: number, vx: number, vz: number, t0: number }
function Games.stack(ctx: Ctx): Micro
	local st = ctx.stage
	local need = 3 + math.floor(ctx.diff / 2)
	local bh = 1
	local tw = MicroStage.TOWER
	local tp = U_DIR * tw.u + V_DIR * tw.v
	local cx, cz = tp.X, tp.Z -- room space of the tower's middle
	local sx, sz = if ctx.tiny then 2.5 else 4, if ctx.tiny then 2.5 else 4 -- the top floor's size
	local ox, oz = 0, 0 -- the top floor's offset from the middle
	local level = 1
	local axis = "x" -- the moving floor slides along this axis
	local speed = (6 + 1.2 * ctx.diff) * ctx.speed
	local mpos, dir = -7, 1
	local done = false
	local label = say(ctx, string.format("Drop the floors! 0/%d", need))
	local m = newMe(-10, 6, RIGHT)
	local function floorThing(w: number, d: number, lv: number): Thing
		return st.adopt(MicroModels.slab(Vector3.new(w, bh, d), FLOOR_COLORS[(lv - 1) % #FLOOR_COLORS + 1], "window"), math.max(w, d) * 0.45)
	end
	local function placeXZ(t: Thing, x: number, z: number, y: number)
		local u, v = uvOf(x, z)
		st.place(t, u, v, y, 0)
	end
	local moving = floorThing(sx, sz, level)
	local rope = st.adopt(MicroModels.slab(Vector3.new(0.25, 1, 0.25), "black"))
	local falling: { Falling } = {}
	local now = 0
	local function topY(): number
		return tw.base + bh * (level - 1)
	end
	local function movingXZ(): (number, number)
		if axis == "x" then
			return cx + mpos, cz + oz
		end
		return cx + ox, cz + mpos
	end
	local function drop()
		if done then
			return
		end
		local cur = mpos
		local base = if axis == "x" then ox else oz
		local size = if axis == "x" then sx else sz
		if math.abs(cur - base) <= 0.2 then
			cur = base -- near enough is perfect
		end
		local lo = math.max(cur - size / 2, base - size / 2)
		local hi = math.min(cur + size / 2, base + size / 2)
		local overlap = hi - lo
		local mx, mz = movingXZ()
		if overlap <= 0.05 then
			done = true
			table.insert(falling, { t = moving, x = mx, z = mz, y = topY(), vy = 0, vx = if axis == "x" then dir * 3 else 0, vz = if axis == "z" then dir * 3 else 0, t0 = now })
			MicroModels.show(rope, false)
			ctx.shake()
			ctx.lose()
			return
		end
		Audio.play("pop", { pitch = 0.8 + level * 0.1 })
		st.remove(moving)
		-- the piece that hangs over falls off
		if overlap < size - 0.05 then
			local cutLo = if cur < base then cur - size / 2 else hi
			local cutW = size - overlap
			local mid = cutLo + cutW / 2
			local chunk = floorThing(if axis == "x" then cutW else sx, if axis == "z" then cutW else sz, level)
			local fx = if axis == "x" then cx + mid else cx + ox
			local fz = if axis == "z" then cz + mid else cz + oz
			local away = if mid > base then 2 else -2
			table.insert(falling, { t = chunk, x = fx, z = fz, y = topY(), vy = 1, vx = if axis == "x" then away else 0, vz = if axis == "z" then away else 0, t0 = now })
		end
		local mid = (lo + hi) / 2
		if axis == "x" then
			sx, ox = overlap, mid
		else
			sz, oz = overlap, mid
		end
		local fixed = floorThing(sx, sz, level)
		placeXZ(fixed, cx + ox, cz + oz, topY())
		local fu, fv = uvOf(cx + ox, cz + oz)
		local pp = st.at(fu, fv, topY() + bh)
		burstAt(ctx, pp, { "white", "steel" }, 6)
		st.puff(st.at(fu, fv, topY()), "dust", 10)
		if overlap >= size - 0.05 then
			popAt(ctx, pp, "Perfect!", "yellow")
			st.puff(pp, "spark", 12)
		end
		UIKit.setText(label, string.format("Drop the floors! %d/%d", level, need))
		if level >= need then
			done = true
			MicroModels.show(rope, false)
			burstAt(ctx, pp, { "yellow", "white", "good" }, 18)
			ctx.win()
			return
		end
		level += 1
		axis = if axis == "x" then "z" else "x"
		dir = if ctx.rng:chance(0.5) then 1 else -1
		mpos = -7 * dir
		moving = floorThing(sx, sz, level)
	end
	goPad(ctx, "Drop!")
	local function animate(t: number, dt: number)
		now = t
		for i = #falling, 1, -1 do
			local f = falling[i]
			f.vy -= 30 * dt
			f.x += f.vx * dt
			f.z += f.vz * dt
			f.y += f.vy * dt
			placeXZ(f.t, f.x, f.z, f.y)
			if t - f.t0 > 1.2 then
				st.remove(f.t)
				table.remove(falling, i)
			end
		end
		m.action = "stand"
		pose(ctx, m, t)
	end
	return {
		clock = 1.5,
		update = function(t: number, dt: number)
			animate(t, dt)
			if done then
				return
			end
			mpos += dir * speed * dt
			if mpos >= 7 then
				mpos, dir = 7, -1
			elseif mpos <= -7 then
				mpos, dir = -7, 1
			end
			local mx, mz = movingXZ()
			local y = topY() + 2.2
			placeXZ(moving, mx, mz, y)
			-- the rope from the crane's jib down to the floor
			MicroModels.scale(rope, Vector3.new(1, math.max(0.2, 16 - y - bh), 1))
			placeXZ(rope, mx, mz, y + bh)
		end,
		key = function(k: string)
			if k == "go" or k == "down" then
				drop()
			end
		end,
		after = function(t: number, won: boolean)
			animate(t, 1 / 60)
			ending(ctx, m, t, won)
		end,
		auto = function()
			local base = if axis == "x" then ox else oz
			if math.abs(mpos - base) <= math.max(0.25, speed * 0.06) then
				drop()
			end
		end,
	}
end

return Games
