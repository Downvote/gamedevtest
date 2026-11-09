--!strict
-- The minigames' arena (GAME_DESIGN 5; docs/ARCHITECTURE.md 10.8): every minigame is a party round, in the spirit of
-- the party games' minigames: the player's founder and three rival founders (five when Crowded) on the idea's stage,
-- all moving freely (hold the arrows or WASD; Space or the action pad to jump, dash or shove), for a round of about
-- half a minute. The engines (UI/MicroGames) bring the rules and the hazards; the arena brings the players, their
-- movement and bumps, the rivals' brains' helpers, the knock-outs, the scores, the scoreboard, the tags over the
-- heads, the touch pads, the Icy floor and the Shrinking walls. Three kinds of round:
--   "survive": hazards knock players out; the last one standing wins, and so does anyone still standing at the end.
--   "score":   the most points at the end wins (a tie for first too).
--   "race":    the first to the finish wins.
-- Room space: (x, z) studs from the middle of the stage's floor, along the world's axes (the floor is a square there:
-- a diamond on the screen), y up from the floor. The keys move along the screen (up is up the screen).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Looks = require(ReplicatedStorage.Shared.Data.Looks)
local Names = require(ReplicatedStorage.Shared.Data.Names)
local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local AvatarView = require(script.Parent.Parent.Controllers.AvatarView)
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
	seconds: number, -- the round's clock
	ice: boolean, -- Icy: everyone slides
	more: number, -- Frenzy: hazards and pickups this many times as often (1 without)
	shrink: boolean, -- Shrinking: the arena closes in
	rivals: number, -- 3, or 5 when Crowded
	sharp: number, -- added to the rivals' skill (Crowded)
	held: { [string]: boolean }, -- the keys and pads held now ("up" "down" "left" "right" "go")
	variant: string,
	pop: (x: number, y: number, text: string, color: Color3) -> (),
	burst: (x: number, y: number, colors: { string }, n: number?) -> (),
	float: (g: GuiObject, vx: number, vy: number, life: number, gravity: number?) -> (),
	flash: (color: string) -> (),
	shake: () -> (), -- a hit's jolt
	win: () -> (),
	lose: () -> (),
	press: (key: string) -> (),
}

-- A player in the round (index 1 is the player's founder).
export type P = {
	i: number,
	me: boolean,
	name: string,
	color: string, -- palette key: their shirt, their scoreboard row, their tiles
	x: number,
	z: number,
	vx: number,
	vz: number,
	y: number,
	vy: number,
	yaw: number,
	alive: boolean,
	outAt: number,
	place: number, -- 0 until placed
	score: number,
	stun: number, -- seconds left dazed (no moving)
	act: string, -- a pose for a moment ("swing", "reach", "cheer", ...)
	actUntil: number,
	skill: number, -- 0 .. 1 (the founder's auto: 1)
	pace: number, -- speed factor
	tx: number, -- a brain's target
	tz: number,
	think: number, -- a brain's next decision
	cool: number, -- the action's cooldown left
	fly: number, -- seconds since knocked out (-1 standing)
	fx: number,
	fz: number,
	fvy: number,
	fy: number,
	rival: MicroStage.Rival?,
	tag: TextLabel?,
	data: { [string]: any },
}

-- Something deadly at (x, z) within r, in t seconds (0: now). `born` is when it showed (the rivals see it later).
export type Danger = { x: number, z: number, r: number, t: number, born: number }

export type Arena = {
	ctx: Ctx,
	st: MicroStage.Stage,
	players: { P },
	me: P,
	mode: string,
	base: number, -- the arena's half size at the start
	lim: number, -- its half size now (Shrinking closes it)
	speed: number, -- studs a second
	grip: number, -- how fast the players reach their speed (Icy: slow)
	t: number,
	seconds: number,
	over: boolean,
	winner: P?,
	tags: boolean, -- scores over the heads
	brain: (p: P, t: number, dt: number) -> (number, number, boolean),
	onAct: (p: P, t: number) -> (),
	onBump: ((a: P, b: P, nx: number, nz: number, hard: number) -> ())?,
	scoreOf: ((p: P) -> string)?,
	label: string, -- what a point is ("coins") for the end's line
	at: (x: number, z: number, y: number) -> Vector3,
	uv: (x: number, z: number) -> (number, number),
	place: (t: Thing, x: number, z: number, y: number, yaw: number?) -> (),
	update: (t: number, dt: number) -> (),
	pose: (t: number) -> (),
	after: (t: number, won: boolean) -> (),
	knock: (p: P, t: number, dx: number?, dz: number?) -> (),
	award: (p: P, n: number, quiet: boolean?) -> (),
	finishRace: (p: P) -> (),
	finish: () -> (boolean, string),
	auto: () -> (),
	key: (k: string) -> (),
	jump: (p: P) -> (),
	head: (p: P) -> Vector3,
	alive: () -> { P },
	others: (p: P) -> { P },
	lift: number, -- the players stand this high (on tiles, in karts)
	walls: boolean, -- Shrinking closes the arena's walls (an engine may shrink something else)
	-- cost(x, z, tt, stay): being at (x, z) tt seconds from now, to stay there (or only passing through)
	safest: (p: P, cost: (x: number, z: number, tt: number, stay: boolean) -> number, spots: { { number } }?) -> (number, number),
	dangerCost: (p: P, dangers: { Danger }) -> (x: number, z: number, tt: number, stay: boolean) -> number,
	steer: (p: P, x: number, z: number) -> (number, number, boolean), -- (dx, dz, false): a brain's answer
	react: (p: P) -> number,
	sees: (p: P, d: Danger) -> boolean,
	popAt: (pos: Vector3, text: string, color: string) -> (),
	pads: (act: string) -> (),
}

local MicroArena = {}

local U_DIR, V_DIR = MicroStage.U_DIR, MicroStage.V_DIR
MicroArena.ROOM = 9.5 -- the arena's half size (room space; the walls stand at 12)
local R = 0.65 -- a player's radius
local JUMP_V = 10
local GRAV = 32
MicroArena.JUMP_V = JUMP_V
MicroArena.GRAV = GRAV
-- the rivals' colours (their shirts); the founder's own shirt colour is left out
local COLORS = { "blue", "green", "pink", "orange", "purple", "berry_red" }
local PAD_Y = 18

function MicroArena.uv(x: number, z: number): (number, number)
	return x * U_DIR.X + z * U_DIR.Z, x * V_DIR.X + z * V_DIR.Z
end

-- a direction along the screen (du right, dv down) -> room space
function MicroArena.xz(du: number, dv: number): (number, number)
	return du * U_DIR.X + dv * V_DIR.X, du * U_DIR.Z + dv * V_DIR.Z
end

function MicroArena.yaw(dx: number, dz: number): number
	return math.atan2(dx, dz)
end

local function ordinal(n: number): string
	return ({ "1st", "2nd", "3rd", "4th", "5th", "6th" })[n] or tostring(n)
end
MicroArena.ordinal = ordinal

-- The round: `mode` ("survive" | "score" | "race"), opts.start: the players' places (room space) or a ring.
export type Opts = { label: string?, act: string?, tags: boolean?, starts: { { number } }?, walls: boolean? }

function MicroArena.new(ctx: Ctx, mode: string, opts: Opts?): Arena
	local o: Opts = opts or {}
	local st = ctx.stage
	local rng = ctx.rng
	local myLook = AvatarView.lookOf(Players.LocalPlayer)
	local myColor = Looks.shirt[myLook.shirt] or "yellow"
	local colors: { string } = {}
	for _, c in COLORS do
		if c ~= myColor then
			table.insert(colors, c)
		end
	end
	local n = 1 + ctx.rivals
	-- the starts: the founder at the front, the rivals round a ring
	local starts: { { number } } = o.starts or {}
	if #starts < n then
		starts = {}
		for i = 1, n do
			local a = math.pi / 2 + (i - 1) / n * math.pi * 2
			local du, dv = math.cos(a) * 5.5, math.sin(a) * 5.5
			local x, z = MicroArena.xz(du, dv)
			table.insert(starts, { x, z })
		end
	end
	local used: { [string]: boolean } = {}
	local function name(): string
		for _ = 1, 20 do
			local nm = Names.first[rng:int(1, #Names.first)]
			if not used[nm] then
				used[nm] = true
				return nm
			end
		end
		return "Rival"
	end
	local players: { P } = {}
	for i = 1, n do
		local s = starts[i]
		local skill = if i == 1 then 1 else math.clamp(0.3 + 0.07 * ctx.diff + ctx.sharp + (rng:next() - 0.5) * 0.16, 0.1, 0.97)
		local p: P = {
			i = i,
			me = i == 1,
			name = if i == 1 then "You" else name(),
			color = if i == 1 then myColor else colors[(i - 2) % #colors + 1],
			x = s[1],
			z = s[2],
			vx = 0,
			vz = 0,
			y = 0,
			vy = 0,
			yaw = MicroArena.yaw(-s[1], -s[2]),
			alive = true,
			outAt = 0,
			place = 0,
			score = 0,
			stun = 0,
			act = "",
			actUntil = 0,
			skill = skill,
			pace = if i == 1 then 1 else 0.86 + 0.12 * skill,
			tx = s[1],
			tz = s[2],
			think = 0,
			cool = 0,
			fly = -1,
			fx = 0,
			fz = 0,
			fvy = 0,
			fy = 0,
			rival = nil,
			tag = nil,
			data = {},
		}
		if i > 1 then
			local look: Types.Look = { skin = rng:int(1, #Looks.skin), hair = rng:int(1, #Looks.hair), style = rng:int(1, #Looks.styles), shirt = table.find(Looks.shirt, p.color) or 1 }
			p.rival = st.rival(look, 0.08 * (i - 1))
		end
		table.insert(players, p)
	end
	local me = players[1]

	local A: Arena
	local area = ctx.area
	local autoUntil = 0
	local finished = false

	-- the scoreboard: a row a player, sorted by standing, top right under the header
	local board = UIKit.plate(area, UDim2.fromOffset(78, 4 + 9 * n), UDim2.fromOffset(ctx.w - 82, 24), UIKit.hex(0x2B2238), 0.15, 1)
	board.Name = "Scoreboard"
	board.ZIndex = 11
	type Row = { f: Frame, name: TextLabel, score: TextLabel, p: P }
	local rows: { Row } = {}
	for _, p in players do
		local f = Instance.new("Frame")
		f.Name = "Row_" .. p.i
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromOffset(76, 9)
		f.ZIndex = 12
		f.Parent = board
		local sw = UIKit.rect(f, UDim2.fromOffset(5, 5), UDim2.fromOffset(2, 2), UIKit.color("ink"), 12)
		UIKit.rect(sw, UDim2.fromOffset(3, 3), UDim2.fromOffset(1, 1), UIKit.color(p.color), 12)
		local nl = UIKit.text(f, p.name, UDim2.fromOffset(50, 9), UDim2.fromOffset(9, 0), { color = if p.me then UIKit.color("accent") else UIKit.color("text"), z = 12, name = "Name" })
		local sl = UIKit.text(f, "", UDim2.fromOffset(28, 9), UDim2.fromOffset(46, 0), { x = "right", color = UIKit.color("text"), z = 12, name = "Score" })
		table.insert(rows, { f = f, name = nl, score = sl, p = p })
	end
	local boardAt = -1
	local function scoreText(p: P): string
		local fn = A.scoreOf
		if fn then
			return fn(p)
		end
		if A.mode == "score" then
			return tostring(math.floor(p.score))
		elseif not p.alive then
			return "OUT"
		end
		return ""
	end
	local function standing(): { P }
		local list = table.clone(players)
		table.sort(list, function(a: P, b: P): boolean
			if A.mode == "survive" then
				if a.alive ~= b.alive then
					return a.alive
				end
				if a.alive then
					return a.i < b.i
				end
				return a.outAt > b.outAt
			end
			if a.score ~= b.score then
				return a.score > b.score
			end
			return a.i < b.i
		end)
		return list
	end
	local function drawBoard(now: number)
		if now - boardAt < 0.2 then
			return
		end
		boardAt = now
		local order = standing()
		for _, r in rows do
			local k = table.find(order, r.p) or 1
			r.f.Position = UDim2.fromOffset(1, 2 + 9 * (k - 1))
			UIKit.setText(r.score, scoreText(r.p))
			UIKit.setTextColor(r.name, if not r.p.alive then UIKit.color("text_dim") elseif r.p.me then UIKit.color("accent") else UIKit.color("text"))
		end
	end

	-- the tags over the heads: "YOU" (and the score) over the founder, the score over the rivals' in score rounds
	for _, p in players do
		if p.me or o.tags then
			p.tag = UIKit.text(area, "", UDim2.fromOffset(40, 10), UDim2.fromOffset(-100, -100), { x = "center", color = UIKit.color(if p.me then "accent" else p.color), kind = "outline", z = 11, name = "Tag" })
		end
	end

	-- Shrinking: four glowing bars mark the walls closing in
	local walls: { Thing } = {}
	if ctx.shrink and o.walls ~= false then
		for i = 1, 4 do
			local bar = MicroModels.slab(Vector3.new(MicroArena.ROOM * 2 + 0.5, 0.5, 0.5), "berry_red", nil, true)
			st.adopt(bar)
			walls[i] = bar
		end
	end

	local function head(p: P): Vector3
		local rig = if p.rival then (p.rival :: MicroStage.Rival).rig else st.avatar.rig
		local hd = rig.parts.Head
		if hd then
			return hd.Position + Vector3.new(0, 1.2, 0)
		end
		local u, v = MicroArena.uv(p.x, p.z)
		return st.at(u, v, 3.5)
	end

	local function posePlayer(p: P, t: number)
		local u, v = MicroArena.uv(p.x, p.z)
		local y = p.y + A.lift
		local action = "stand"
		local sp = math.sqrt(p.vx * p.vx + p.vz * p.vz)
		local k = 0
		if p.fly >= 0 then
			y = p.fy + A.lift
			action = "hurt"
			sp = 0
		elseif p.y > 0.02 then
			action = "jump"
		elseif p.stun > 0 then
			action = "hurt"
			sp = 0
		elseif p.actUntil > t then
			action = p.act
			k = math.clamp(1 - (p.actUntil - t) / 0.3, 0, 1)
		end
		if p.fly > 1.1 and not p.me then
			local rv = p.rival
			if rv then
				rv.hide()
			end
			return
		end
		if p.rival then
			(p.rival :: MicroStage.Rival).pose(u, v, y, p.yaw, t, sp, action, k)
		else
			st.pose(u, v, y, p.yaw, t, sp, action, k)
		end
	end

	local function placeTags(t: number)
		for _, p in players do
			local tag = p.tag
			if tag then
				local show = p.alive and p.fly < 0
				if show then
					local x, y = st.screen(head(p))
					local txt = if p.me then (if A.mode == "score" then "YOU " .. scoreText(p) else "YOU") else scoreText(p)
					UIKit.setText(tag, txt)
					tag.Size = UDim2.fromOffset(UIKit.textWidth(txt) + 4, 10)
					tag.Position = UDim2.fromOffset(x - math.floor(tag.Size.X.Offset / 2), y - 12)
					tag.Visible = true
				else
					tag.Visible = false
				end
			end
		end
		local _ = t
	end

	local function endWith(won: boolean)
		if finished then
			return
		end
		finished = true
		A.over = true
		if won then
			ctx.win()
		else
			ctx.lose()
		end
	end

	local function inputDir(): (number, number)
		local hd = ctx.held
		local du = (if hd.right then 1 else 0) - (if hd.left then 1 else 0)
		local dv = (if hd.down then 1 else 0) - (if hd.up then 1 else 0)
		return MicroArena.xz(du, dv)
	end

	A = {
		ctx = ctx,
		st = st,
		players = players,
		me = me,
		mode = mode,
		base = MicroArena.ROOM,
		lim = MicroArena.ROOM,
		speed = 8.5 * ctx.speed,
		grip = if ctx.ice then 2.4 else 18,
		t = 0,
		seconds = ctx.seconds,
		over = false,
		winner = nil,
		tags = o.tags == true,
		lift = 0,
		walls = o.walls ~= false,
		brain = function(_p: P, _t: number, _dt: number): (number, number, boolean)
			return 0, 0, false
		end,
		onAct = function(p: P, _t: number)
			A.jump(p)
		end,
		onBump = nil,
		scoreOf = nil,
		label = o.label or "points",
		at = function(x: number, z: number, y: number): Vector3
			local u, v = MicroArena.uv(x, z)
			return st.at(u, v, y)
		end,
		uv = MicroArena.uv,
		place = function(t: Thing, x: number, z: number, y: number, yaw: number?)
			local u, v = MicroArena.uv(x, z)
			st.place(t, u, v, y, yaw)
		end,
		update = function(t: number, dt: number)
			A.t = t
			if ctx.shrink and A.walls then
				A.lim = A.base - (A.base - 4.5) * math.clamp(t / math.max(1, A.seconds), 0, 1)
				local L = A.lim + 0.5
				local k = (L * 2 + 0.5) / (MicroArena.ROOM * 2 + 0.5)
				for i, bar in walls do
					MicroModels.scale(bar, Vector3.new(k, 1, 1))
					local sx = if i == 1 then 0 elseif i == 2 then 0 elseif i == 3 then -L else L
					local sz = if i == 1 then -L elseif i == 2 then L else 0
					A.place(bar, sx, sz, 0, if i >= 3 then math.pi / 2 else 0)
				end
			end
			local auto = os.clock() < autoUntil
			for _, p in players do
				if p.fly >= 0 then
					p.fly += dt
					p.fvy -= GRAV * dt
					p.fy = math.max(0, p.fy + p.fvy * dt)
					if p.fy > 0 then
						p.x += p.fx * dt
						p.z += p.fz * dt
					end
					if p.fly > 1.1 and p.fly - dt <= 1.1 and not p.me then
						st.puff(A.at(p.x, p.z, 0.6), "smoke", 8)
					end
					continue
				end
				if not p.alive then
					continue
				end
				p.stun = math.max(0, p.stun - dt)
				p.cool = math.max(0, p.cool - dt)
				local dx, dz, act = 0, 0, false
				if p.me and not auto then
					dx, dz = inputDir()
				else
					dx, dz, act = A.brain(p, t, dt)
				end
				if act and p.stun <= 0 then
					A.onAct(p, t)
				end
				local mag = math.sqrt(dx * dx + dz * dz)
				if mag > 1 then
					dx, dz = dx / mag, dz / mag
				end
				local sp = if p.stun > 0 then 0 else A.speed * p.pace
				local kk = math.min(1, A.grip * dt)
				p.vx += (dx * sp - p.vx) * kk
				p.vz += (dz * sp - p.vz) * kk
				p.x += p.vx * dt
				p.z += p.vz * dt
				if p.y > 0 or p.vy > 0 then
					p.vy -= GRAV * dt
					p.y += p.vy * dt
					if p.y <= 0 then
						p.y, p.vy = 0, 0
						st.puff(A.at(p.x, p.z, 0.2), "dust", 3)
					end
				end
				if mag > 0.1 and p.stun <= 0 then
					p.yaw = MicroArena.yaw(dx, dz)
				end
				local L = A.lim
				if math.abs(p.x) > L then
					p.x = math.clamp(p.x, -L, L)
					p.vx *= -0.3
				end
				if math.abs(p.z) > L then
					p.z = math.clamp(p.z, -L, L)
					p.vz *= -0.3
				end
			end
			-- bumps: players push each other apart (and an engine may do more)
			for i = 1, #players do
				local a = players[i]
				if a.alive and a.fly < 0 then
					for j = i + 1, #players do
						local b = players[j]
						if b.alive and b.fly < 0 and math.abs(a.y - b.y) < 1.2 then
							local dx, dz = b.x - a.x, b.z - a.z
							local d = math.sqrt(dx * dx + dz * dz)
							if d < R * 2 and d > 1e-4 then
								local nx, nz = dx / d, dz / d
								local over = R * 2 - d
								a.x -= nx * over / 2
								a.z -= nz * over / 2
								b.x += nx * over / 2
								b.z += nz * over / 2
								local rel = (b.vx - a.vx) * nx + (b.vz - a.vz) * nz
								local hard = 0
								if rel < 0 then
									local e = if ctx.ice then 0.9 else 0.4
									local j2 = -(1 + e) * rel / 2
									a.vx -= j2 * nx
									a.vz -= j2 * nz
									b.vx += j2 * nx
									b.vz += j2 * nz
									hard = -rel
								end
								local fn = A.onBump
								if fn then
									fn(a, b, nx, nz, hard)
								end
							end
						end
					end
				end
			end
			for _, p in players do
				posePlayer(p, t)
			end
			placeTags(t)
			drawBoard(os.clock())
			-- the last one standing
			if A.mode == "survive" and not finished then
				local left = A.alive()
				if #left == 1 and #players > 1 then
					A.winner = left[1]
					left[1].place = 1
					endWith(left[1].me)
				elseif #left == 0 then
					endWith(false)
				end
			end
		end,
		pose = function(t: number)
			for _, p in players do
				posePlayer(p, t)
			end
			placeTags(t)
			drawBoard(os.clock())
		end,
		after = function(t: number, won: boolean)
			local dt = 1 / 60
			for _, p in players do
				if p.fly >= 0 then
					p.fly += dt
					p.fvy -= GRAV * dt
					p.fy = math.max(0, p.fy + p.fvy * dt)
					if p.fy > 0 then
						p.x += p.fx * dt
						p.z += p.fz * dt
					end
				elseif p.alive then
					p.vx, p.vz = 0, 0
					p.y = math.max(0, p.y - 0.25)
					local top = if A.mode == "survive" then p.alive elseif A.winner then A.winner == p else p.place == 1
					p.act, p.actUntil = if top then "cheer" else "hurt", t + 10
					if p.me then
						p.act = if won then "cheer" else "hurt"
						if won then
							p.yaw = MicroStage.FACE_VIEWER
						end
					end
				end
				posePlayer(p, t)
			end
			placeTags(t)
			drawBoard(os.clock() + 1)
		end,
		knock = function(p: P, t: number, dx: number?, dz: number?)
			if not p.alive then
				return
			end
			p.alive = false
			p.outAt = t
			p.place = #A.alive() + 1
			p.fly = 0
			local ox, oz = dx or p.x, dz or p.z
			local d = math.max(0.1, math.sqrt(ox * ox + oz * oz))
			p.fx, p.fz = ox / d * 5, oz / d * 5
			p.fvy, p.fy = 9, p.y
			st.puff(A.at(p.x, p.z, 1), "debris", 10)
			st.puff(A.at(p.x, p.z, 1.5), "spark", 6)
			Audio.play("squish", { pitch = if p.me then 0.8 else 1.1 })
			A.popAt(head(p), if p.me then "OUT!" else p.name .. " out!", if p.me then "bad" else p.color)
			if p.me then
				ctx.shake()
				ctx.flash("bad")
				if A.mode == "survive" then
					endWith(false)
				end
			end
		end,
		award = function(p: P, n: number, quiet: boolean?)
			p.score = math.max(0, p.score + n)
			if not quiet then
				A.popAt(head(p), (if n >= 0 then "+" else "") .. tostring(n), if n >= 0 then (if p.me then "accent" else p.color) else "bad")
			end
			if p.me and n > 0 then
				Audio.play("coin", { pitch = 1 + math.min(0.5, p.score * 0.02) })
			end
		end,
		finishRace = function(p: P)
			if finished then
				return
			end
			p.place = 1
			A.winner = p
			A.popAt(head(p), if p.me then "FIRST!" else p.name .. " wins!", if p.me then "good" else p.color)
			endWith(p.me)
		end,
		-- the clock ran out: who won, and the line under the stamp
		finish = function(): (boolean, string)
			local order = standing()
			if A.mode == "survive" then
				local left = A.alive()
				for _, p in left do
					p.place = 1
				end
				if me.alive then
					return true, if #left == 1 then "Last one standing!" else "Still standing!"
				end
				return false, "Out in " .. ordinal(me.place)
			elseif A.mode == "race" then
				-- the first one there, or (nobody made it) the furthest along: the engine's score is the progress
				local w = A.winner
				if w then
					return w == me, if w == me then "First one there!" else w.name .. " got there first"
				end
				for k, p in order do
					p.place = k
				end
				A.winner = order[1]
				return order[1] == me, if order[1] == me then "Furthest along!" else ordinal(table.find(order, me) or #order) .. " place"
			end
			local top = order[1].score
			local k = 1
			for i, p in order do
				if i > 1 and p.score < order[i - 1].score then
					k = i
				end
				p.place = k
			end
			local won = me.score >= top and me.score > 0
			return won, string.format("%s place: %d %s", ordinal(me.place), math.floor(me.score), A.label)
		end,
		auto = function()
			autoUntil = os.clock() + 0.2
		end,
		key = function(k: string)
			if k == "go" and me.alive and me.stun <= 0 and not finished then
				A.onAct(me, A.t)
			end
		end,
		jump = function(p: P)
			if p.y <= 0.01 and p.vy <= 0 then
				p.vy = JUMP_V
				p.y = 0.02
				if p.me then
					Audio.play("pop", { pitch = 1.3 })
				end
			end
		end,
		head = head,
		alive = function(): { P }
			local out = {}
			for _, p in players do
				if p.alive then
					table.insert(out, p)
				end
			end
			return out
		end,
		others = function(p: P): { P }
			local out = {}
			for _, q in players do
				if q ~= p and q.alive then
					table.insert(out, q)
				end
			end
			return out
		end,
		-- The rivals' and the auto player's dodging: the cheapest spot near and far (or among `spots`) by the engine's
		-- cost of being there `tt` seconds from now, the way there counted too, not too far, not in a corner.
		safest = function(p: P, cost: (x: number, z: number, tt: number, stay: boolean) -> number, spots: { { number } }?): (number, number)
			local L = A.lim - 0.4
			local spd = A.speed * p.pace
			local best, bx, bz = math.huge, p.x, p.z
			local function try(cx: number, cz: number)
				cx, cz = math.clamp(cx, -L, L), math.clamp(cz, -L, L)
				local dx, dz = cx - p.x, cz - p.z
				local dist = math.sqrt(dx * dx + dz * dz)
				local tt = dist / math.max(1, spd)
				local c = dist * 0.04 + (math.max(0, math.abs(cx) - L + 2) + math.max(0, math.abs(cz) - L + 2)) * 0.15
				c += cost(cx, cz, tt, true)
				-- the way there, a step a stud
				local steps = math.min(10, math.floor(dist / 1.0))
				for k = 1, steps do
					if c >= best then
						break
					end
					local f = k / (steps + 1)
					c += cost(p.x + dx * f, p.z + dz * f, tt * f, false) * 0.8
				end
				-- keep to the spot already chosen unless another is clearly better
				if math.abs(cx - p.tx) < 0.05 and math.abs(cz - p.tz) < 0.05 then
					c -= 0.3
				end
				if c < best then
					best, bx, bz = c, cx, cz
				end
			end
			try(p.x, p.z)
			try(p.tx, p.tz)
			if spots then
				for _, sp in spots do
					try(sp[1], sp[2])
				end
			else
				for a = 0, 7 do
					local an = a / 8 * math.pi * 2
					try(p.x + math.cos(an) * 1.6, p.z + math.sin(an) * 1.6)
					try(p.x + math.cos(an) * 3.5, p.z + math.sin(an) * 3.5)
				end
				for gx = -2, 2 do
					for gz = -2, 2 do
						try(gx * L / 2, gz * L / 2)
					end
				end
			end
			return bx, bz
		end,
		-- the cost of a spot from dangers (the ones this player has seen): deadly if one hits it after the player gets
		-- there, a little when one is near
		dangerCost = function(p: P, dangers: { Danger }): (x: number, z: number, tt: number, stay: boolean) -> number
			local seen: { Danger } = {}
			for _, d in dangers do
				if A.sees(p, d) then
					table.insert(seen, d)
				end
			end
			return function(x: number, z: number, tt: number, stay: boolean): number
				local c = 0
				for _, d in seen do
					local r = d.r + R + 0.25
					local ex, ez = x - d.x, z - d.z
					local q = ex * ex + ez * ez
					-- staying: it hits after the player gets there; passing: it hits while they are there
					local hits = if stay then d.t > tt - 0.2 else math.abs(d.t - tt) < 0.35
					if q < r * r and hits then
						c += 10 + 5 / (0.2 + d.t)
					elseif stay and q < (r + 1) * (r + 1) then
						c += 0.4 / (0.3 + d.t)
					end
				end
				return c
			end
		end,
		-- the direction to a point, slowing when nearly there
		steer = function(p: P, x: number, z: number): (number, number, boolean)
			local dx, dz = x - p.x, z - p.z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < 0.15 then
				return 0, 0, false
			end
			local k = math.min(1, d / 0.8)
			return dx / d * k, dz / d * k, false
		end,
		-- seconds before a rival's next decision (quicker when sharper)
		react = function(p: P): number
			if p.me then
				return 0
			end
			return 0.12 + (1 - p.skill) * 0.4 + rng:next() * 0.08
		end,
		-- whether a danger has shown long enough for this player to see it
		sees = function(p: P, d: Danger): boolean
			if p.me then
				return true
			end
			return A.t - d.born >= (1 - p.skill) * 0.55
		end,
		popAt = function(pos: Vector3, text: string, color: string)
			local x, y = st.screen(pos)
			ctx.pop(x, y - 8, text, UIKit.color(color))
		end,
		-- the touch pads: a cross of arrows at the bottom left (held), the action at the bottom right
		pads = function(act: string)
			local s = 15
			local cx, cy = 8 + s, ctx.h - PAD_Y - s * 2 - 2
			local keys = { "up", "down", "left", "right" }
			local ox = { 0, 0, -1, 1 }
			local oy = { -1, 1, 0, 0 }
			for k, key in keys do
				local b = UIKit.button(area, "", UDim2.fromOffset(s, s), UDim2.fromOffset(cx + ox[k] * (s + 1), cy + oy[k] * (s + 1)), function() end, { name = "Pad_" .. key, color = UIKit.color("plate_light") })
				b.ZIndex = 10
				local plate = b:FindFirstChild("Plate") or b
				PixelSprites.image(plate, "arrow_" .. key .. "_t", UDim2.fromOffset(4, 4), 4)
				b.MouseButton1Down:Connect(function()
					ctx.held[key] = true
				end)
				b.MouseButton1Up:Connect(function()
					ctx.held[key] = false
				end)
				b.MouseLeave:Connect(function()
					ctx.held[key] = false
				end)
			end
			local aw = math.max(40, UIKit.textWidth(act) + 12)
			local go = UIKit.button(area, act, UDim2.fromOffset(aw, 22), UDim2.fromOffset(ctx.w - aw - 8, ctx.h - PAD_Y - 24), function() end, { name = "Pad_go", color = UIKit.color("accent") })
			go.ZIndex = 10
			go.MouseButton1Down:Connect(function()
				ctx.press("go")
			end)
		end,
	}
	A.pads(o.act or "Jump")
	return A
end

return MicroArena
