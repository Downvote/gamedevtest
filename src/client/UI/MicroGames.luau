--!strict
-- The minigames (GAME_DESIGN 5; docs/ARCHITECTURE.md 10.8): eleven party-round engines, each played by one or more
-- ideas in their own theme (Data/Ideas micro + variant). In the spirit of the party games' minigames: the player's
-- founder and three rival founders (UI/MicroArena) on the idea's 3D stage (UI/MicroStage), free movement, about half
-- a minute a round, last one standing, most points or first to the finish. An engine gets a context (the stage, the
-- overlay, the difficulty 1..8 from the idea's rarity, the modifiers' effects: Turbo's speed, Icy, Crowded, Frenzy,
-- Shrinking; an Rng seeded by the server) and its arena calls ctx.win() or ctx.lose() as soon as the round is
-- decided; when the clock runs out first, `finish()` says who won. `after(t, won)` keeps everyone moving under the
-- stamp. The rivals get sharper and the hazards thicker with the difficulty.
--
-- Room space (UI/MicroArena): (x, z) from the floor's middle along the world's axes, y up.
--
-- Every engine is lost by doing nothing (the hazards aim at the player, the rivals score, the bomb starts in the
-- player's hands) and won by `auto` (the sims' player: the rivals' brains at full skill, one frame at a time).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MicroModels = require(ReplicatedStorage.Shared.Models.MicroModels)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local MicroStage = require(script.Parent.MicroStage)
local Arena = require(script.Parent.MicroArena)

type Thing = MicroModels.Thing
type P = Arena.P
type Danger = Arena.Danger

export type Ctx = Arena.Ctx

export type Micro = {
	update: (t: number, dt: number) -> (), -- dt 0: before GO (everyone in place)
	key: (k: string) -> (), -- "go" (the action) | "up" | "down" | "left" | "right"
	finish: () -> (boolean, string), -- the clock ran out: won?, the line under the stamp
	after: (t: number, won: boolean) -> (), -- once it is over
	auto: () -> (), -- the sims' player takes this frame
	rule: string, -- one line on the curtain under the order
}

local Games = {}

local ROOM = Arena.ROOM

------------------------------------------------------------------ helpers
local function dist(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

local function wrap(A: Arena.Arena, rule: string, step: (t: number, dt: number) -> (), after: ((t: number) -> ())?): Micro
	return {
		update = function(t: number, dt: number)
			if dt > 0 and not A.over then
				step(t, dt)
				A.update(t, dt)
			else
				A.pose(t)
			end
		end,
		key = A.key,
		finish = A.finish,
		after = function(t: number, won: boolean)
			if after then
				after(t)
			end
			A.after(t, won)
		end,
		auto = A.auto,
		rule = rule,
	}
end

-- A line under the header (the call, the question).
local function say(ctx: Ctx, text: string, color: string?): TextLabel
	return UIKit.text(ctx.area, text, UDim2.fromOffset(ctx.w - 180, 10), UDim2.fromOffset(90, 26), { x = "center", color = UIKit.color(color or "text"), kind = "outline", z = 12, name = "Say" })
end

-- A floor of n x n tiles (MicroModels.grid) and its helpers; flush() once a frame.
type Tiles = {
	thing: Thing,
	n: number,
	step: number,
	center: (i: number) -> (number, number),
	index: (x: number, z: number) -> number,
	color: (i: number, color: string, neon: boolean?) -> (),
	drop: (i: number, y: number) -> (),
	spots: () -> { { number } },
	flush: () -> (),
}
local function tiles(A: Arena.Arena, n: number, step: number, size: number, color: string): Tiles
	local st = A.st
	local g = MicroModels.grid(n, step, size, 0.25, color)
	st.adopt(g)
	A.place(g, 0, 0, -0.2)
	local half = n * step / 2
	local dirty = false
	local T: Tiles
	T = {
		thing = g,
		n = n,
		step = step,
		center = function(i: number): (number, number)
			local r = (i - 1) // n + 1
			local c = (i - 1) % n + 1
			return (c - (n + 1) / 2) * step, (r - (n + 1) / 2) * step
		end,
		index = function(x: number, z: number): number
			local c = math.clamp(math.floor((x + half) / step) + 1, 1, n)
			local r = math.clamp(math.floor((z + half) / step) + 1, 1, n)
			return (r - 1) * n + c
		end,
		color = function(i: number, c: string, neon: boolean?)
			local p = g.parts["T" .. i]
			if p then
				local col = UIKit.color(c)
				local mat = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
				if p.Color ~= col or p.Material ~= mat then
					p.Color = col
					p.Material = mat
					g.colors["T" .. i] = col
					dirty = true
				end
			end
		end,
		drop = function(i: number, y: number)
			local x, z = T.center(i)
			g.rest["T" .. i] = CFrame.new(x, 0.125 + y, z)
		end,
		spots = function(): { { number } }
			local out = {}
			for i = 1, n * n do
				local x, z = T.center(i)
				table.insert(out, { x, z })
			end
			return out
		end,
		flush = function()
			A.place(g, 0, 0, -0.2)
			if dirty then
				dirty = false
				st.refresh(g)
			end
		end,
	}
	return T
end

-- A thing dropped from `top` lands in `fall` seconds: its height at age a.
local function fallY(a: number, fall: number, top: number): number
	local k = math.clamp(a / fall, 0, 1)
	return top * (1 - k * k)
end

-- whether a 1/f-second tick boundary was crossed this frame
local function every(t: number, dt: number, f: number): boolean
	return math.floor(t * f) ~= math.floor((t - dt) * f)
end

------------------------------------------------------------------ 1. bombs: things rain down (Action, Space, Dinosaurs)
-- Crates (meteors, the aliens' bombs) fall on marked spots, aimed at the players more and more often; one hit and you
-- are out. Last one standing wins.
local BOMB_SKIN: { [string]: { kind: string, warn: string, puff: string, word: string } } = {
	blocks = { kind = "crate", warn = "berry_red", puff = "debris", word = "crates" },
	space = { kind = "bomb", warn = "purple", puff = "spark", word = "bombs" },
	dino = { kind = "meteor", warn = "orange", puff = "ember", word = "meteors" },
}
type Drop = { t: Thing, mark: Thing, x: number, z: number, at: number, land: number, done: boolean, r: number }
function Games.bombs(ctx: Ctx): Micro
	local A = Arena.new(ctx, "survive", { act = "Jump" })
	local st = ctx.stage
	local rng = ctx.rng
	local skin = BOMB_SKIN[ctx.variant] or BOMB_SKIN.blocks
	local drops: { Drop } = {}
	local nextAt = 1.0
	local salvoAt = 7
	local function warnTime(t: number): number
		return math.max(0.75, (1.35 - 0.05 * ctx.diff - 0.25 * t / A.seconds) / ctx.speed)
	end
	local function drop(t: number, x: number, z: number)
		local L = A.lim
		x, z = math.clamp(x, -L, L), math.clamp(z, -L, L)
		local r = 1.7
		local mark = st.spawn("spot", { color = skin.warn })
		MicroModels.scale(mark, Vector3.new(r * 2 / 2.5, 1, r * 2 / 2.5))
		A.place(mark, x, z, 0.02)
		local th = st.spawn(skin.kind, nil, 1.2)
		table.insert(drops, { t = th, mark = mark, x = x, z = z, at = t, land = t + warnTime(t), done = false, r = r })
	end
	local function target(t: number)
		local roll = rng:next()
		local tgt: P? = nil
		if roll < 0.35 and A.me.alive then
			tgt = A.me
		elseif roll < 0.7 then
			local left = A.alive()
			tgt = left[rng:int(1, #left)]
		end
		if tgt then
			local w = warnTime(t)
			drop(t, tgt.x + tgt.vx * w * 0.35 + (rng:next() - 0.5) * 1.2, tgt.z + tgt.vz * w * 0.35 + (rng:next() - 0.5) * 1.2)
		else
			drop(t, (rng:next() * 2 - 1) * A.lim, (rng:next() * 2 - 1) * A.lim)
		end
	end
	local function dangers(): { Danger }
		local out: { Danger } = {}
		for _, d in drops do
			if not d.done then
				table.insert(out, { x = d.x, z = d.z, r = d.r, t = math.max(0, d.land - A.t), born = d.at })
			end
		end
		return out
	end
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		if t >= p.think then
			p.think = t + A.react(p)
			p.tx, p.tz = A.safest(p, A.dangerCost(p, dangers()))
		end
		return A.steer(p, p.tx, p.tz)
	end
	local function step(t: number, _dt: number)
		if t >= nextAt then
			nextAt = t + math.max(0.2, (0.85 - 0.06 * ctx.diff) * (1 - 0.45 * t / A.seconds) / ctx.more / ctx.speed)
			target(t)
		end
		if t >= salvoAt then
			-- a ring round someone
			salvoAt = t + math.max(3.5, 7 - 0.3 * ctx.diff)
			local left = A.alive()
			local p = if rng:next() < 0.5 and A.me.alive then A.me else left[rng:int(1, #left)]
			for k = 0, 4 do
				local a = k / 5 * math.pi * 2 + rng:next()
				drop(t, p.x + math.cos(a) * 3, p.z + math.sin(a) * 3)
			end
		end
		for i = #drops, 1, -1 do
			local d = drops[i]
			if not d.done then
				local y = fallY(t - d.at, d.land - d.at, 16)
				A.place(d.t, d.x, d.z, y, if skin.kind == "crate" then 0 else (t - d.at) * 4)
				-- the mark blinks faster as it comes
				MicroModels.show(d.mark, math.floor(t * (if d.land - t < 0.4 then 16 else 7)) % 2 == 0)
				if t >= d.land then
					d.done = true
					st.puff(A.at(d.x, d.z, 0.5), skin.puff, 10)
					st.puff(A.at(d.x, d.z, 0.4), "dust", 6)
					local near = dist(d.x, d.z, A.me.x, A.me.z)
					Audio.play(if skin.kind == "crate" then "squish" else "pop", { pitch = 0.6 + rng:next() * 0.2, volume = math.clamp(1.2 - near / 12, 0.2, 1) })
					if near < 5 then
						ctx.shake()
					end
					for _, p in A.players do
						if p.alive and p.y < 1.4 and dist(p.x, p.z, d.x, d.z) < d.r + 0.4 then
							A.knock(p, t, p.x - d.x, p.z - d.z)
						end
					end
					st.remove(d.mark)
				end
			elseif t > d.land + 0.35 then
				st.remove(d.t)
				table.remove(drops, i)
			end
		end
	end
	return wrap(A, "Dodge the falling " .. skin.word .. ". Last one standing wins!", step)
end

------------------------------------------------------------------ 2. collect: grab the most (Animals, Pirates, Ocean)
-- Coins (fish, treats) drop all over; walk over them to grab them, the shiny ones worth three. Bombs (jellies, crabs)
-- roll about from difficulty 2: touch one and you are dazed and drop two. Most at the end wins.
local GRAB_SKIN: { [string]: { good: string, rare: string, bad: string, word: string, badWord: string } } = {
	pet = { good = "yarn", rare = "star", bad = "crab", word = "treats", badWord = "crabs" },
	loot = { good = "coin", rare = "gem", bad = "bomb", word = "coins", badWord = "bombs" },
	fish = { good = "fish", rare = "star", bad = "jelly", word = "fish", badWord = "jellies" },
}
type Item = { t: Thing, x: number, z: number, at: number, worth: number, bad: boolean, vx: number, vz: number, gone: boolean }
function Games.collect(ctx: Ctx): Micro
	local skin = GRAB_SKIN[ctx.variant] or GRAB_SKIN.loot
	local A = Arena.new(ctx, "score", { act = "Jump", tags = true, label = skin.word })
	local st = ctx.stage
	local rng = ctx.rng
	local items: { Item } = {}
	local want = math.floor(5 + 2 * ctx.more)
	local nBad = if ctx.diff >= 2 then math.floor((ctx.diff - 1) / 3 + 1) * (if ctx.more > 1 then 2 else 1) else 0
	local function spawn(t: number, bad: boolean)
		local L = A.lim - 0.6
		local x, z = (rng:next() * 2 - 1) * L, (rng:next() * 2 - 1) * L
		local rare = not bad and rng:next() < 0.12 + 0.02 * ctx.diff
		local th = st.spawn(if bad then skin.bad elseif rare then skin.rare else skin.good, nil, 0.8)
		local a = rng:next() * math.pi * 2
		local sp = if bad then 1.2 + 0.25 * ctx.diff else 0
		table.insert(items, { t = th, x = x, z = z, at = t, worth = if rare then 3 else 1, bad = bad, vx = math.cos(a) * sp, vz = math.sin(a) * sp, gone = false })
	end
	for _ = 1, want do
		spawn(-1, false)
	end
	for _ = 1, nBad do
		spawn(-1, true)
	end
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		local held = p.data.item :: Item?
		if t >= p.think or (held and held.gone) then
			p.think = t + A.react(p)
			local best, pick = -math.huge, nil :: Item?
			local noisy = not p.me and rng:next() < (1 - p.skill) * 0.5
			for _, it in items do
				if not it.bad and not it.gone and (it.at < 0 or t - it.at > 0.3) then
					local mine = dist(p.x, p.z, it.x, it.z) / (A.speed * p.pace)
					local value = it.worth / (mine + 0.4)
					-- someone else gets there first: less worth it
					for _, q in A.players do
						if q ~= p and dist(q.x, q.z, it.x, it.z) / (A.speed * q.pace) < mine - 0.15 then
							value *= 0.35
							break
						end
					end
					if noisy then
						value = rng:next()
					end
					if value > best then
						best, pick = value, it
					end
				end
			end
			p.data.item = pick
			if pick then
				p.tx, p.tz = pick.x, pick.z
			else
				p.tx, p.tz = 0, 0
			end
		end
		local dx, dz = A.steer(p, p.tx, p.tz)
		-- keep clear of the bad ones
		for _, it in items do
			if it.bad and not it.gone then
				local ex, ez = p.x - it.x, p.z - it.z
				local d = math.sqrt(ex * ex + ez * ez)
				if d < 2.6 and d > 0.01 then
					local k = (2.6 - d) / 2.6 * (if p.me then 2.2 else 1.2 * p.skill)
					dx += ex / d * k
					dz += ez / d * k
				end
			end
		end
		return dx, dz, false
	end
	local function step(t: number, dt: number)
		local good = 0
		for _, it in items do
			if not it.bad and not it.gone then
				good += 1
			end
		end
		if good < want then
			spawn(t, false)
		end
		for i = #items, 1, -1 do
			local it = items[i]
			if it.gone then
				st.remove(it.t)
				table.remove(items, i)
				continue
			end
			if it.bad then
				it.x += it.vx * dt * ctx.speed
				it.z += it.vz * dt * ctx.speed
				local L = A.lim - 0.5
				if math.abs(it.x) > L then
					it.vx = -it.vx
					it.x = math.clamp(it.x, -L, L)
				end
				if math.abs(it.z) > L then
					it.vz = -it.vz
					it.z = math.clamp(it.z, -L, L)
				end
			end
			local y = if it.at < 0 then 0 else fallY(t - it.at, 0.4, 7)
			local bob = if it.bad then 0 else math.abs(math.sin(t * 3 + i)) * 0.3
			A.place(it.t, it.x, it.z, y + bob, t * 1.5 + i)
			if y < 0.5 then
				for _, p in A.players do
					if p.alive and p.y < 1 and p.stun <= 0 and dist(p.x, p.z, it.x, it.z) < 1.2 then
						it.gone = true
						if it.bad then
							p.stun = 1.2
							local lost = math.min(2, math.floor(p.score))
							A.award(p, -lost)
							st.puff(A.at(it.x, it.z, 0.8), "spark", 10)
							st.puff(A.at(it.x, it.z, 0.6), "smoke", 3)
							Audio.play("squish", { pitch = 0.9 })
							if p.me then
								ctx.shake()
							end
							-- what was dropped lands round about, and the bad one comes back elsewhere
							for _ = 1, lost do
								spawn(t, false)
							end
							spawn(t, true)
						else
							A.award(p, it.worth)
							st.puff(A.at(it.x, it.z, 0.6), if it.worth > 1 then "twinkle" else "spark", if it.worth > 1 then 6 else 4)
						end
						break
					end
				end
			end
		end
	end
	return wrap(A, "Grab the most " .. skin.word .. "! Keep clear of the " .. skin.badWord .. ".", step)
end

------------------------------------------------------------------ 3. tiles: the floor gives way (Puzzle, Cooking, Rhythm)
-- A floor of tiles. Puzzle: a colour is called; stand on it before the others drop. Cooking: hot plates glow, then
-- burn. Rhythm: the floor lights up in patterns to the beat, then zaps. Caught on a bad tile and you are out; last
-- one standing wins.
local TILE_COLORS = { "berry_red", "blue", "yellow", "green" }
local TILE_NAMES: { [string]: string } = { berry_red = "RED", blue = "BLUE", yellow = "YELLOW", green = "GREEN" }
function Games.tiles(ctx: Ctx): Micro
	local A = Arena.new(ctx, "survive", { act = "Jump" })
	local st = ctx.stage
	local rng = ctx.rng
	local N = 5
	local T = tiles(A, N, 3.8, 3.5, "plastic")
	A.lift = 0.1
	local mode = if ctx.variant == "flip" then "hot" elseif ctx.variant == "beat" then "beat" else "call"
	local count = N * N
	-- per tile: when it turns deadly (math.huge: never), until when, and when its warning started
	local deadAt: { number } = table.create(count, math.huge)
	local deadUntil: { number } = table.create(count, -1)
	local warnAt: { number } = table.create(count, math.huge)
	local colorOf: { string } = table.create(count, "plastic")
	local call: TextLabel = say(ctx, "", "text")
	local nextRound = 1.2
	local round = 0
	local beatLen = 0.6 / ctx.speed
	local lastBeat = -1
	local base = if mode == "hot" then "steel" elseif mode == "beat" then "purple" else "plastic"
	for i = 1, count do
		T.color(i, base)
	end
	local function warnLen(): number
		return math.max(1.1, (3.0 - 0.17 * ctx.diff) * 0.93 ^ round / ctx.speed)
	end
	local function newRound(t: number)
		round += 1
		if mode == "call" then
			local k = if ctx.diff >= 4 then 4 else 3
			local safe = TILE_COLORS[rng:int(1, k)]
			for i = 1, count do
				colorOf[i] = TILE_COLORS[rng:int(1, k)]
			end
			for _ = 1, 3 do
				colorOf[rng:int(1, count)] = safe
			end
			local w = warnLen()
			for i = 1, count do
				T.color(i, colorOf[i])
				if colorOf[i] ~= safe then
					warnAt[i] = t
					deadAt[i] = t + w
					deadUntil[i] = t + w + 1.1
				end
			end
			UIKit.setText(call, "Stand on " .. TILE_NAMES[safe] .. "!")
			UIKit.setTextColor(call, UIKit.color(safe))
			Audio.play("ding", { pitch = 1.2 })
			nextRound = t + w + 1.9
		else
			local n = math.clamp(math.floor((6 + ctx.diff + round) * ctx.more), 6, count - 4)
			local w = math.max(0.9, warnLen() * 0.6)
			local order = {}
			for i = 1, count do
				table.insert(order, i)
			end
			for i = #order, 2, -1 do
				local j = rng:int(1, i)
				order[i], order[j] = order[j], order[i]
			end
			-- a hot plate under someone more often than not
			local left = A.alive()
			local p = if rng:next() < 0.5 and A.me.alive then A.me else left[rng:int(1, #left)]
			if p then
				local at = table.find(order, T.index(p.x, p.z))
				if at then
					order[at], order[1] = order[1], order[at]
				end
			end
			for c = 1, n do
				local i = order[c]
				warnAt[i] = t
				deadAt[i] = t + w
				deadUntil[i] = t + w + 0.9
			end
			UIKit.setText(call, "Hot plates!")
			UIKit.setTextColor(call, UIKit.color("orange"))
			nextRound = t + w + math.max(0.5, 1.4 - 0.08 * ctx.diff)
		end
	end
	-- Rhythm: a pattern lights on a beat and zaps two beats later
	local PATTERNS: { (r: number, c: number, k: number) -> boolean } = {
		function(r: number, _c: number, k: number): boolean
			return r % 2 == k % 2
		end,
		function(_r: number, c: number, k: number): boolean
			return c % 2 == k % 2
		end,
		function(r: number, c: number, k: number): boolean
			return (r + c) % 2 == k % 2
		end,
		function(r: number, c: number, _k: number): boolean
			return r == 1 or r == N or c == 1 or c == N
		end,
		function(r: number, c: number, _k: number): boolean
			return r ~= 1 and r ~= N and c ~= 1 and c ~= N
		end,
		function(r: number, c: number, k: number): boolean
			return r == (k * 2 % N) + 1 or c == ((k * 2 + 2) % N) + 1
		end,
	}
	local function beat(t: number, b: number)
		Audio.play(if b % 2 == 0 then "tick" else "key", { pitch = 1 + (b % 4) * 0.12 })
		-- the idle floor pulses
		for i = 1, count do
			if warnAt[i] == math.huge and deadUntil[i] < t then
				local r, c = (i - 1) // N + 1, (i - 1) % N + 1
				T.color(i, if (r + c + b) % 2 == 0 then "purple" else "pink")
			end
		end
		local gap = if ctx.diff >= 5 then 2 else 3
		if b >= 2 and b % gap == 0 then
			local pat = PATTERNS[rng:int(1, #PATTERNS)]
			local k = rng:int(0, 1)
			local w = beatLen * (if ctx.diff >= 6 then 1.5 else 2)
			for i = 1, count do
				local r, c = (i - 1) // N + 1, (i - 1) % N + 1
				if pat(r, c, k) and deadUntil[i] < t then
					warnAt[i] = t
					deadAt[i] = t + w
					deadUntil[i] = t + w + beatLen
				end
			end
		end
	end
	local function dangers(): { Danger }
		local out: { Danger } = {}
		for i = 1, count do
			if deadUntil[i] > A.t then
				local x, z = T.center(i)
				table.insert(out, { x = x, z = z, r = 1.55, t = math.max(0, deadAt[i] - A.t), born = warnAt[i] })
			end
		end
		return out
	end
	local spots = T.spots()
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		if t >= p.think then
			p.think = t + A.react(p)
			p.tx, p.tz = A.safest(p, A.dangerCost(p, dangers()), spots)
		end
		return A.steer(p, p.tx, p.tz)
	end
	local function step(t: number, dt: number)
		if mode == "beat" then
			local b = math.floor(t / beatLen)
			if b ~= lastBeat then
				lastBeat = b
				beat(t, b)
				UIKit.setText(call, if b % 2 == 0 then "Dance!" else "")
				UIKit.setTextColor(call, UIKit.color("pink"))
			end
		elseif t >= nextRound then
			newRound(t)
		end
		for i = 1, count do
			local x, z = T.center(i)
			if t >= deadAt[i] and t < deadUntil[i] then
				-- deadly now
				if mode == "call" then
					T.drop(i, -math.min(3, (t - deadAt[i]) * 14))
				elseif mode == "hot" then
					T.color(i, if math.floor(t * 10) % 2 == 0 then "orange" else "berry_red", true)
					if every(t, dt, 6) then
						st.puff(A.at(x, z, 0.4), "ember", 1)
					end
				else
					T.color(i, "white", true)
				end
				if t - dt < deadAt[i] then
					if mode == "hot" then
						st.puff(A.at(x, z, 0.5), "ember", 3)
					elseif mode == "beat" then
						st.puff(A.at(x, z, 0.4), "spark", 2)
					end
				end
				for _, p in A.players do
					if p.alive and p.y < 0.15 and T.index(p.x, p.z) == i then
						A.knock(p, t, p.x, p.z)
					end
				end
			elseif t >= deadUntil[i] and deadUntil[i] > 0 then
				-- back to normal
				deadAt[i], deadUntil[i], warnAt[i] = math.huge, -1, math.huge
				T.drop(i, 0)
				T.color(i, if mode == "call" then colorOf[i] else base)
			elseif warnAt[i] <= t then
				-- the warning: it blinks
				local blink = math.floor(t * (if deadAt[i] - t < 0.5 then 14 else 6)) % 2 == 0
				if mode == "call" then
					T.drop(i, if blink then -0.08 else 0)
				elseif mode == "hot" then
					T.color(i, if blink then "orange" else base, blink)
				else
					T.color(i, if blink then "white" else "purple", blink)
				end
			end
		end
		T.flush()
	end
	local rules: { [string]: string } = { call = "Stand on the called colour before the floor drops!", hot = "Keep off the hot plates!", beat = "Keep off the lit tiles when they zap!" }
	return wrap(A, rules[mode] .. " Last one standing wins.", step)
end

------------------------------------------------------------------ 4. quiz: run to the answer (School, Detectives)
-- A question; four pads with an answer each. Run onto the right one before the time is up: a point for everyone on
-- it, one more for the first there. The wrong pads buck you off. Most points wins.
function Games.quiz(ctx: Ctx): Micro
	local A = Arena.new(ctx, "score", { act = "Jump", tags = true, label = "answers" })
	local st = ctx.stage
	local rng = ctx.rng
	local PADS = { { -4.6, -4.6 }, { 4.6, -4.6 }, { -4.6, 4.6 }, { 4.6, 4.6 } }
	local PAD_COLORS = { "blue", "green", "yellow", "pink" }
	local pads: { Thing } = {}
	local labels: { TextLabel } = {}
	for i, at in PADS do
		local pd = MicroModels.slab(Vector3.new(4.25, 0.25, 4.25), PAD_COLORS[i])
		st.adopt(pd)
		A.place(pd, at[1], at[2], -0.15)
		pads[i] = pd
		labels[i] = UIKit.text(ctx.area, "", UDim2.fromOffset(40, 18), UDim2.fromOffset(-100, -100), { x = "center", face = "big", kind = "outline", color = UIKit.color("white"), z = 9, name = "Opt_" .. i })
	end
	local q = say(ctx, "", "text")
	local spot = ctx.variant == "spot"
	local suspects: { Thing } = {}
	local answer = 1
	local endAt = 1.0
	local first: P? = nil
	local open = false
	local function ask(t: number)
		answer = rng:int(1, 4)
		if spot then
			-- the suspects: three alike, one in an odd coat
			local coat = ({ "wood", "steel", "purple", "green" })[rng:int(1, 4)]
			local odd = ({ "berry_red", "yellow", "blue", "pink" })[rng:int(1, 4)]
			for i, at in PADS do
				local sp = suspects[i]
				if sp == nil then
					sp = st.spawn("suspect", nil, 1)
					suspects[i] = sp
				end
				MicroModels.recolor(sp, if i == answer then odd else coat)
				st.refresh(sp)
				A.place(sp, at[1] + 1.4, at[2] - 1.4, 0.1, MicroStage.FACE_VIEWER)
				UIKit.setText(labels[i], "")
			end
			UIKit.setText(q, "Which suspect is the odd one out?")
		else
			local a, b, op = rng:int(2, 9 + ctx.diff), rng:int(2, 9), "+"
			local right = a + b
			if ctx.diff >= 3 and rng:next() < 0.5 then
				op, right = "-", a
				a = a + b
			end
			if ctx.diff >= 5 and rng:next() < 0.4 then
				a, b = rng:int(2, 9), rng:int(2, 9)
				op, right = "x", a * b
			end
			local used: { [number]: boolean } = { [right] = true }
			for i = 1, 4 do
				local v = right
				if i ~= answer then
					repeat
						v = right + ({ -10, -2, -1, 1, 2, 10 })[rng:int(1, 6)]
					until not used[v] and v >= 0
					used[v] = true
				end
				UIKit.setText(labels[i], tostring(v))
			end
			UIKit.setText(q, string.format("%d %s %d = ?", a, op, b))
		end
		Audio.play("ding", { pitch = 1.1 })
		endAt = t + math.max(2.6, (5.2 - 0.3 * ctx.diff) / ctx.speed)
		first = nil
		open = true
		for _, p in A.players do
			-- each rival makes up their mind after a moment, right as often as they are sharp
			p.data.choice = if p.me then answer elseif rng:next() < 0.45 + 0.5 * p.skill then answer else rng:int(1, 4)
			p.data.decide = if p.me then 0 else t + 0.5 + (1 - p.skill) * 1.6 + rng:next() * 0.5
		end
	end
	local function padOf(p: P): number
		for i, at in PADS do
			if math.abs(p.x - at[1]) < 2.2 and math.abs(p.z - at[2]) < 2.2 then
				return i
			end
		end
		return 0
	end
	for _, p in A.players do
		p.data.waitX = p.x * 0.4
		p.data.waitZ = p.z * 0.4
	end
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		if open and t >= (p.data.decide or 0) then
			local at = PADS[p.data.choice or 1]
			-- not everyone on the pad's very middle
			return A.steer(p, at[1] + ((p.i % 2) - 0.5) * 1.6, at[2] + ((p.i // 2 % 2) - 0.5) * 1.6)
		end
		return A.steer(p, p.data.waitX or 0, p.data.waitZ or 0)
	end
	local function step(t: number, _dt: number)
		if not open and t >= endAt then
			ask(t)
		end
		for i, at in PADS do
			local x, y = st.screen(A.at(at[1], at[2], 0.4))
			labels[i].Position = UDim2.fromOffset(x - 20, y - 9)
		end
		if open then
			for _, p in A.players do
				if first == nil and padOf(p) == answer and p.y < 0.2 then
					first = p
				end
			end
			if t >= endAt then
				open = false
				endAt = t + 1.3
				st.flash(pads[answer], 0.6)
				st.puff(A.at(PADS[answer][1], PADS[answer][2], 0.6), "confetti", 14)
				for _, p in A.players do
					local k = padOf(p)
					if k == answer then
						A.award(p, if p == first then 2 else 1)
						p.act, p.actUntil = "cheer", t + 0.8
					elseif k > 0 then
						-- a wrong pad bucks you off
						p.vy = Arena.JUMP_V * 0.8
						p.y = 0.05
						p.stun = 0.7
						st.puff(A.at(p.x, p.z, 0.4), "smoke", 2)
					end
				end
				Audio.play(if padOf(A.me) == answer then "combo" else "deny")
				UIKit.setText(q, if spot then "That one!" else "= " .. labels[answer].Text)
			end
		end
	end
	return wrap(A, "Run onto the right answer! First one there gets a bonus.", step)
end

------------------------------------------------------------------ 5. sweep: jump the beam (Adventure, Fantasy, Robots)
-- A log (a magic beam, a laser) sweeps round the room from a post in the middle, faster and faster, a second one from
-- difficulty 4: jump it as it comes. Hit and you are out; last one standing wins.
local SWEEP_SKIN: { [string]: { color: string, neon: boolean, post: string, cap: string, word: string } } = {
	leap = { color = "wood", neon = false, post = "wood_dark", cap = "leaf", word = "log" },
	cast = { color = "purple", neon = true, post = "steel_dark", cap = "pink", word = "beam" },
	program = { color = "berry_red", neon = true, post = "steel", cap = "screen_on", word = "laser" },
}
function Games.sweep(ctx: Ctx): Micro
	local A = Arena.new(ctx, "survive", { act = "Jump" })
	local st = ctx.stage
	local rng = ctx.rng
	local skin = SWEEP_SKIN[ctx.variant] or SWEEP_SKIN.leap
	local post = st.spawn("pillar", { color = skin.post, alt = skin.cap }, 1.2)
	A.place(post, 0, 0, 0)
	local LEN = 15
	local n = 1 + (if ctx.diff >= 4 then 1 else 0) + (if ctx.more > 1 then 1 else 0)
	local beams: { Thing } = {}
	local angles: { number } = {}
	for i = 1, n do
		local b = MicroModels.slab(Vector3.new(LEN, 0.6, 0.6), skin.color, nil, skin.neon)
		st.adopt(b, 0.6)
		beams[i] = b
		angles[i] = (i - 1) / n * math.pi * 2 + rng:next() * 0.4
	end
	local dir = if rng:next() < 0.5 then 1 else -1
	local TOP = 0.95
	local function omega(t: number): number
		return dir * (1.0 + 0.08 * ctx.diff) * (1 + 0.6 * math.clamp(t / A.seconds, 0, 1)) * ctx.speed
	end
	local reversed = false
	-- seconds until the nearest beam reaches angle a
	local function arrival(a: number, w: number): number
		local best = math.huge
		for _, b in angles do
			local d = ((a - b) * (if w > 0 then 1 else -1)) % (math.pi * 2)
			best = math.min(best, d / math.abs(w))
		end
		return best
	end
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		local w = omega(t)
		local a = math.atan2(p.z, p.x)
		local tt = arrival(a, w)
		if p.data.err == nil or t >= (p.data.errAt or 0) then
			p.data.err = if p.me then 0 else (rng:next() - 0.5) * (1 - p.skill) * 0.55
			p.data.errAt = t + 0.8
		end
		local jump = p.y <= 0.01 and tt < 0.32 + (p.data.err :: number) and tt > 0.14
		-- drift about a little (the auto player stands still while a beam comes)
		if p.me and tt < 0.9 then
			return 0, 0, jump
		end
		if t >= p.think then
			p.think = t + 1.2 + rng:next()
			local r = 3.5 + rng:next() * math.max(0.5, A.lim - 4)
			local an = a + (rng:next() - 0.5) * 1.2
			p.tx, p.tz = math.cos(an) * r, math.sin(an) * r
		end
		local dx, dz = A.steer(p, p.tx, p.tz)
		return dx * 0.5, dz * 0.5, jump
	end
	local function step(t: number, dt: number)
		if not reversed and ctx.diff >= 6 and t > A.seconds * 0.5 then
			reversed = true
			dir = -dir
			Audio.play("notice")
			st.puff(A.at(0, 0, 2.5), "spark", 12)
		end
		local w = omega(t)
		for i, b in beams do
			local a0 = angles[i]
			local a1 = a0 + w * dt
			angles[i] = a1
			local cx, cz = math.cos(a1) * (LEN / 2 + 1), math.sin(a1) * (LEN / 2 + 1)
			-- a slab along +X turned to the angle a1 in room space
			MicroModels.place(b, CFrame.new(A.at(cx, cz, 0.3)) * CFrame.Angles(0, -a1, 0))
			for _, p in A.players do
				if p.alive and p.y < TOP then
					local pa = math.atan2(p.z, p.x)
					local r = math.sqrt(p.x * p.x + p.z * p.z)
					local crossed = ((pa - a0) * (if w > 0 then 1 else -1)) % (math.pi * 2) <= math.abs(w * dt) + 0.03
					if crossed and r > 0.8 and r < LEN + 1.2 then
						local s = if w > 0 then 1 else -1
						A.knock(p, t, -math.sin(a1) * s, math.cos(a1) * s)
					end
				end
			end
			if skin.neon and every(t, dt, 8) then
				local rr = 2 + rng:next() * 10
				st.puff(A.at(math.cos(a1) * rr, math.sin(a1) * rr, 0.6), "spark", 1)
			end
		end
		-- the post pushes players out
		for _, p in A.players do
			local r = math.sqrt(p.x * p.x + p.z * p.z)
			if r < 1.6 and r > 0.01 then
				p.x, p.z = p.x / r * 1.6, p.z / r * 1.6
			end
		end
	end
	return wrap(A, "Jump the " .. skin.word .. " as it sweeps round! Last one standing wins.", step)
end

------------------------------------------------------------------ 6. sumo: bump them out (Racing)
-- Bumper karts in a ring of kerbs: Dash! rams the kart ahead; out of the ring and you are out. Last one standing wins.
function Games.sumo(ctx: Ctx): Micro
	local A = Arena.new(ctx, "survive", { act = "Dash!", walls = false })
	local st = ctx.stage
	A.base, A.lim = 11.4, 11.4
	A.lift = 0.55
	A.grip = if ctx.ice then 1.4 else 3.2
	A.speed = 7.5 * ctx.speed
	local R0 = 8.3
	local ring = R0
	local hoop = MicroModels.hoop(R0 + 0.4, 28, "berry_red", "white")
	st.adopt(hoop)
	A.place(hoop, 0, 0, 0)
	local karts: { [P]: Thing } = {}
	for _, p in A.players do
		karts[p] = st.spawn("kart", { color = p.color }, 1.2)
	end
	A.onAct = function(p: P, _t: number)
		if p.cool > 0 then
			return
		end
		p.cool = 1.0
		p.vx += math.sin(p.yaw) * 13
		p.vz += math.cos(p.yaw) * 13
		st.puff(A.at(p.x - math.sin(p.yaw) * 1.2, p.z - math.cos(p.yaw) * 1.2, 0.4), "dust", 4)
		if p.me then
			Audio.play("pop", { pitch = 0.8 })
		end
	end
	A.onBump = function(a: P, b: P, nx: number, nz: number, hard: number)
		if hard > 2 then
			-- the faster one shoves the other along
			local va = a.vx * nx + a.vz * nz
			local vb = -(b.vx * nx + b.vz * nz)
			local push = hard * 0.5
			if va > vb then
				b.vx += nx * push
				b.vz += nz * push
			else
				a.vx -= nx * push
				a.vz -= nz * push
			end
			st.puff(A.at((a.x + b.x) / 2, (a.z + b.z) / 2, 1), "spark", 5)
			Audio.play("squish", { pitch = 1.2 + math.min(0.4, hard * 0.03), volume = 0.7 })
		end
	end
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		local r = math.sqrt(p.x * p.x + p.z * p.z)
		-- the edge first
		if r > ring - (if p.me then 2.4 else 1.2 + 1.2 * p.skill) then
			return -p.x / math.max(0.1, r), -p.z / math.max(0.1, r), false
		end
		if t >= p.think then
			p.think = t + A.react(p)
			local best, pick = math.huge, nil :: P?
			for _, q in A.others(p) do
				local d = dist(p.x, p.z, q.x, q.z)
				local qr = math.sqrt(q.x * q.x + q.z * q.z)
				local score = d - qr * 0.6
				if score < best then
					best, pick = score, q
				end
			end
			p.data.target = pick
		end
		local q = p.data.target :: P?
		if q == nil or not q.alive then
			return A.steer(p, 0, 0)
		end
		-- the auto player holds the middle, meets a ram head on, and only goes for one near the edge
		if p.me then
			if r > 2.2 then
				return A.steer(p, 0, 0)
			end
			for _, o in A.others(p) do
				local d = math.max(0.1, dist(p.x, p.z, o.x, o.z))
				local ux, uz = (o.x - p.x) / d, (o.z - p.z) / d
				local closing = -((o.vx - p.vx) * ux + (o.vz - p.vz) * uz)
				if d < 4.5 and (closing > 3 or d < 2.2) then
					local face = math.sin(p.yaw) * ux + math.cos(p.yaw) * uz
					return ux, uz, face > 0.7 and p.cool <= 0
				end
			end
			local qr0 = math.sqrt(q.x * q.x + q.z * q.z)
			if qr0 < ring - 3 or dist(p.x, p.z, q.x, q.z) > 5 then
				return A.steer(p, 0, 0)
			end
		end
		-- come at it from the middle's side, then ram
		local qr = math.max(0.1, math.sqrt(q.x * q.x + q.z * q.z))
		local ox, oz = q.x / qr, q.z / qr
		local d = math.max(0.1, dist(p.x, p.z, q.x, q.z))
		local tx, tz = (q.x - p.x) / d, (q.z - p.z) / d
		local aligned = tx * ox + tz * oz
		local face = math.sin(p.yaw) * tx + math.cos(p.yaw) * tz
		local ram = d < 3.2 and aligned > (if p.me then 0.4 else 0.2 - 0.3 * (1 - p.skill)) and face > 0.8 and p.cool <= 0
		if d < 3.2 and aligned > 0 then
			return tx, tz, ram
		end
		return A.steer(p, q.x - ox * 1.8, q.z - oz * 1.8)
	end
	local function placeKarts()
		for _, p in A.players do
			local k = karts[p]
			if p.fly >= 0 then
				A.place(k, p.x, p.z, if p.fly > 1.1 then -60 else p.fy, p.yaw + p.fly * 8)
			else
				A.place(k, p.x, p.z, p.y, p.yaw)
			end
		end
	end
	local function step(t: number, _dt: number)
		if ctx.shrink then
			ring = R0 - (R0 - 4.5) * math.clamp(t / A.seconds, 0, 1)
			local k = (ring + 0.4) / (R0 + 0.4)
			MicroModels.scale(hoop, Vector3.new(k, 1, k))
		end
		placeKarts()
		for _, p in A.players do
			-- a kart tops out
			local sp = math.sqrt(p.vx * p.vx + p.vz * p.vz)
			if sp > 15 then
				p.vx, p.vz = p.vx / sp * 15, p.vz / sp * 15
			end
			if p.alive and math.sqrt(p.x * p.x + p.z * p.z) > ring + 0.4 then
				A.knock(p, t, p.x, p.z)
			end
		end
	end
	return wrap(A, "Ram the others out of the ring! Last one standing wins.", step, function(_t: number)
		placeKarts()
	end)
end

------------------------------------------------------------------ 7. zone: hold the ring (Sports, Music)
-- A glowing ring (a spotlight) on the floor, moving on now and then: the one nearest its middle scores. Shove!
-- pushes the others out of the way. Most points wins.
function Games.zone(ctx: Ctx): Micro
	local A = Arena.new(ctx, "score", { act = "Shove!", tags = true, label = "points" })
	local st = ctx.stage
	local rng = ctx.rng
	local ring = st.spawn("ring", { color = if ctx.variant == "simon" then "pink" else "yellow" })
	local nextRing = st.spawn("ring", { color = "white" })
	MicroModels.show(nextRing, false)
	local zx, zz = 0, 0
	local nx, nz = 0, 0
	local hold = math.max(3.2, 6 - 0.3 * ctx.diff) / ctx.speed
	local moveAt = hold
	local hinted = false
	local tickAt = 0
	local drift = ctx.diff >= 5
	local R2 = 2.5
	local status = say(ctx, "", "text")
	-- the next spot: well away from this one (as far as the room allows: Shrinking closes it in)
	local function pickNext()
		local L = math.max(0.5, A.lim - 3)
		local best = -1
		for _ = 1, 8 do
			local x, z = (rng:next() * 2 - 1) * L, (rng:next() * 2 - 1) * L
			local d = dist(x, z, zx, zz)
			if d > best then
				best, nx, nz = d, x, z
			end
			if d > 5 then
				break
			end
		end
	end
	pickNext()
	-- a shove winds up first (the arm pulls back: a sharp eye can step aside), then lunges the way it faces
	A.onAct = function(p: P, t: number)
		if p.cool > 0 then
			return
		end
		p.cool = 1.0
		p.data.lunge = t + 0.22
		p.act, p.actUntil = "swing", t + 0.45
		if p.me then
			Audio.play("pop", { pitch = 0.9 })
		end
	end
	local function lunges(t: number)
		for _, p in A.players do
			local at = p.data.lunge
			if at and t >= at then
				p.data.lunge = nil
				p.vx += math.sin(p.yaw) * 12
				p.vz += math.cos(p.yaw) * 12
			end
		end
	end
	A.onBump = function(a: P, b: P, bx: number, bz: number, hard: number)
		if hard > 3.5 then
			local va = a.vx * bx + a.vz * bz
			local vb = -(b.vx * bx + b.vz * bz)
			local victim = if va > vb then b else a
			local s = if victim == b then 1 else -1
			victim.vx += bx * s * hard * 0.8
			victim.vz += bz * s * hard * 0.8
			victim.stun = 0.45
			st.puff(A.at(victim.x, victim.z, 1), "spark", 4)
			Audio.play("squish", { pitch = 1.3, volume = 0.6 })
		end
	end
	local function inside(p: P): boolean
		return p.alive and dist(p.x, p.z, zx, zz) < R2
	end
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		if t >= p.think then
			p.think = t + A.react(p)
			if p.data.hint ~= moveAt then
				-- a rival notices the next spot (once a spot), as often as they are sharp
				p.data.hint = moveAt
				p.data.sawNext = rng:next() < p.skill * 0.6
			end
			-- (the auto player holds on until it is just time to go)
			local goNext = hinted and (if p.me then dist(p.x, p.z, nx, nz) / A.speed >= moveAt - t - 0.15 else p.data.sawNext)
			local gx, gz = if goNext then nx else zx, if goNext then nz else zz
			-- spread round the ring's middle (the auto player: the very middle)
			local spread = if p.me then 0 else 1.2
			p.tx, p.tz = gx + (rng:next() - 0.5) * spread, gz + (rng:next() - 0.5) * spread
		end
		local dx, dz = A.steer(p, p.tx, p.tz)
		-- the auto player steps aside from a shove winding up at it
		if p.me then
			for _, q in A.others(p) do
				local d = math.max(0.1, dist(p.x, p.z, q.x, q.z))
				local fx, fz = math.sin(q.yaw), math.cos(q.yaw)
				local facing = ((p.x - q.x) * fx + (p.z - q.z) * fz) / d
				if q.data.lunge and d < 3.5 and facing > 0.75 then
					local sx, sz = -fz, fx
					-- the side toward the ring's middle
					if (zx - p.x) * sx + (zz - p.z) * sz < 0 then
						sx, sz = -sx, -sz
					end
					return sx, sz, false
				end
			end
		end
		-- shove one sharing the ring
		local shove = false
		if inside(p) and p.cool <= 0 then
			-- shove one nearer the middle (a rival makes up their mind now and then, as often as they are sharp)
			local mine = dist(p.x, p.z, zx, zz)
			if not p.me and t >= (p.data.shoveAt or 0) then
				p.data.shoveAt = t + A.react(p) + 0.4
				p.data.keen = rng:next() < p.skill * 0.45
			end
			if p.me or p.data.keen then
				for _, q in A.others(p) do
					local d = math.max(0.1, dist(p.x, p.z, q.x, q.z))
					-- (the auto player shoves anyone close before they shove it)
					if inside(q) and d < 2.6 and (dist(q.x, q.z, zx, zz) < mine + 0.3 or (p.me and q.stun <= 0 and d < 2.2)) then
						local fx, fz = (q.x - p.x) / d, (q.z - p.z) / d
						dx, dz = fx, fz
						shove = math.sin(p.yaw) * fx + math.cos(p.yaw) * fz > 0.7
						break
					end
				end
			end
		end
		return dx, dz, shove
	end
	local function step(t: number, dt: number)
		lunges(t)
		if drift then
			zx += math.sin(t * 0.7) * dt * 0.8
			zz += math.cos(t * 0.53) * dt * 0.8
		end
		if not hinted and t >= moveAt - 1.5 then
			hinted = true
			MicroModels.show(nextRing, true)
			A.place(nextRing, nx, nz, 0.02)
		end
		if t >= moveAt then
			zx, zz = nx, nz
			st.puff(A.at(zx, zz, 0.3), "twinkle", 6)
			Audio.play("ding", { pitch = 1.3 })
			moveAt = t + hold
			hinted = false
			MicroModels.show(nextRing, false)
			pickNext()
		end
		local L = A.lim - 2.5
		zx, zz = math.clamp(zx, -L, L), math.clamp(zz, -L, L)
		A.place(ring, zx, zz, 0.02, t * 1.2)
		local who: { P } = {}
		for _, p in A.players do
			if inside(p) then
				table.insert(who, p)
			end
		end
		if t >= tickAt then
			tickAt = t + 0.5
			-- the one nearest the middle holds it
			local king: P? = nil
			local kd = math.huge
			for _, p in who do
				local d = dist(p.x, p.z, zx, zz)
				if d < kd and p.stun <= 0 then
					king, kd = p, d
				end
			end
			if king then
				A.award(king, 1, true)
				st.puff(A.at(zx, zz, 0.4), "twinkle", 2)
				if king.me then
					Audio.play("tick", { pitch = 1.5 })
				end
			end
			UIKit.setText(status, if king then king.name .. " holds it!" else "")
			UIKit.setTextColor(status, UIKit.color(if king then king.color else "text_dim"))
		end
	end
	return wrap(A, "Hold the middle of the ring to score! Shove the others out.", step)
end

------------------------------------------------------------------ 8. barrage: dodge the volleys (RPG, Ninjas)
-- Arrows (throwing stars) fly across the room from the walls, aimed at someone or in walls with a gap: a red line
-- shows each one's path first. Step aside or jump them. Hit and you are out; last one standing wins.
type Shot = { t: Thing?, line: Thing, x0: number, z0: number, dx: number, dz: number, at: number, fire: number, s: number, speed: number }
function Games.barrage(ctx: Ctx): Micro
	local A = Arena.new(ctx, "survive", { act = "Jump" })
	local st = ctx.stage
	local rng = ctx.rng
	local kind = if ctx.variant == "fruit" then "shuriken" else "arrow"
	local shots: { Shot } = {}
	local nextAt = 1.0
	local SPAN = 26
	local function warn(t: number): number
		return math.max(0.6, (1.1 - 0.04 * ctx.diff - 0.2 * t / A.seconds) / ctx.speed)
	end
	-- one shot from the wall behind (x0, z0) along (dx, dz)
	local function shoot(t: number, x0: number, z0: number, dx: number, dz: number)
		local line = MicroModels.slab(Vector3.new(0.3, 0.1, SPAN), "berry_red", nil, true)
		st.adopt(line)
		A.place(line, x0 + dx * SPAN / 2, z0 + dz * SPAN / 2, 0.02, Arena.yaw(dx, dz))
		table.insert(shots, { t = nil, line = line, x0 = x0, z0 = z0, dx = dx, dz = dz, at = t, fire = t + warn(t), s = 0, speed = (13 + 0.9 * ctx.diff) * ctx.speed })
	end
	local function fromWall(side: number, along: number): (number, number, number, number)
		local E = 12
		if side == 1 then
			return along, -E, 0, 1
		elseif side == 2 then
			return along, E, 0, -1
		elseif side == 3 then
			return -E, along, 1, 0
		end
		return E, along, -1, 0
	end
	local function volley(t: number)
		local roll = rng:next()
		local left = A.alive()
		local tgt = if rng:next() < 0.4 and A.me.alive then A.me else left[rng:int(1, #left)]
		local n = 6
		if roll < 0.45 then
			-- aimed singles at one player, from one or two walls
			for k = 1, (if ctx.diff >= 4 then 2 else 1) do
				local side = rng:int(1, 4)
				local along = if side <= 2 then tgt.x else tgt.z
				local x0, z0, dx, dz = fromWall(side, along + (rng:next() - 0.5) * 0.8)
				shoot(t + (k - 1) * 0.15, x0, z0, dx, dz)
			end
		else
			-- a wall of shots with a gap
			local side = rng:int(1, 4)
			local gap = rng:int(1, n - 1)
			for k = 1, n do
				if k ~= gap and (k ~= gap + 1 or ctx.diff < 6) then
					local x0, z0, dx, dz = fromWall(side, -ROOM + (k - 0.5) * (2 * ROOM / n))
					shoot(t, x0, z0, dx, dz)
				end
			end
			if roll > 0.85 and ctx.diff >= 3 then
				local s2 = if side <= 2 then rng:int(3, 4) else rng:int(1, 2)
				local g2 = rng:int(1, n)
				for k = 1, n do
					if k ~= g2 then
						local x0, z0, dx, dz = fromWall(s2, -ROOM + (k - 0.5) * (2 * ROOM / n))
						shoot(t + 0.6, x0, z0, dx, dz)
					end
				end
			end
		end
	end
	-- the cost of being at (x, z) tt seconds from now: a shot passing there after the player arrives
	local function cost(p: P): (x: number, z: number, tt: number, stay: boolean) -> number
		local list: { Shot } = {}
		for _, s in shots do
			if p.me or A.t - s.at >= (1 - p.skill) * 0.5 then
				table.insert(list, s)
			end
		end
		return function(x: number, z: number, tt: number, stay: boolean): number
			local c = 0
			for _, s in list do
				local rx, rz = x - s.x0, z - s.z0
				local along = rx * s.dx + rz * s.dz
				local side = math.abs(rx * s.dz - rz * s.dx)
				if side < 1.6 and along > s.s - 1 then
					local when = math.max(0, s.fire - A.t) + (along - s.s) / s.speed
					if (stay and when > tt - 0.25) or (not stay and math.abs(when - tt) < 0.4) then
						c += 10 + 4 / (0.2 + math.max(0, when))
					end
				end
			end
			return c
		end
	end
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		if t >= p.think then
			p.think = t + A.react(p)
			p.tx, p.tz = A.safest(p, cost(p))
		end
		-- jump one about to hit
		local jump = false
		for _, s in shots do
			if t >= s.fire then
				local rx, rz = p.x - s.x0, p.z - s.z0
				local ahead = rx * s.dx + rz * s.dz - s.s
				local side = math.abs(rx * s.dz - rz * s.dx)
				local tt = ahead / s.speed
				if p.y <= 0.01 and side < 0.95 and tt > 0.12 and tt < 0.28 + (if p.me then 0 else (1 - p.skill) * 0.2) then
					jump = p.me or rng:next() < p.skill
				end
			end
		end
		local dx, dz = A.steer(p, p.tx, p.tz)
		return dx, dz, jump
	end
	local function step(t: number, dt: number)
		if t >= nextAt then
			nextAt = t + math.max(0.7, (2.1 - 0.13 * ctx.diff) * (1 - 0.3 * t / A.seconds) / ctx.more / ctx.speed)
			volley(t)
		end
		for i = #shots, 1, -1 do
			local s = shots[i]
			if t >= s.fire then
				if s.t == nil then
					s.t = st.spawn(kind, { color = "berry_red" }, 0.6)
					st.remove(s.line)
					if dist(s.x0, s.z0, A.me.x, A.me.z) < 14 then
						Audio.play("flip", { pitch = 1.4 + rng:next() * 0.3, volume = 0.5 })
					end
				end
				local s0 = s.s
				s.s += s.speed * dt
				A.place(s.t :: Thing, s.x0 + s.dx * s.s, s.z0 + s.dz * s.s, 0, if kind == "shuriken" then t * 18 else Arena.yaw(s.dx, s.dz))
				for _, p in A.players do
					if p.alive and p.y < 0.85 then
						local rx, rz = p.x - s.x0, p.z - s.z0
						local along = rx * s.dx + rz * s.dz
						local side = math.abs(rx * s.dz - rz * s.dx)
						if side < 0.85 and along > s0 - 1.1 and along < s.s + 1.1 then
							A.knock(p, t, s.dx, s.dz)
						end
					end
				end
				if s.s > SPAN then
					st.remove(s.t :: Thing)
					table.remove(shots, i)
				end
			else
				MicroModels.show(s.line, math.floor(t * (if s.fire - t < 0.3 then 16 else 8)) % 2 == 0)
			end
		end
	end
	return wrap(A, "Dodge the " .. (if kind == "shuriken" then "throwing stars" else "arrows") .. ": step aside or jump! Last one standing wins.", step)
end

------------------------------------------------------------------ 9. horde: outrun the zombies (Zombies)
-- Zombies climb out of the ground at the edges, more and more of them, each shambling after the nearest founder
-- (slower than you, but they never stop); jump one to get past it. One bite and you turn into one of them. Last one
-- standing wins, and so does anyone still human at the end.
type Zombie = { t: Thing, x: number, z: number, vx: number, vz: number, born: number, target: P?, think: number }
function Games.horde(ctx: Ctx): Micro
	local A = Arena.new(ctx, "survive", { act = "Jump" })
	local st = ctx.stage
	local rng = ctx.rng
	local zombies: { Zombie } = {}
	local MAX = 3 + ctx.diff // 3 + (if ctx.more > 1 then 2 else 0)
	local pace = math.min(0.72, 0.45 + 0.03 * ctx.diff)
	local nextAt = 0.5
	local gap = math.max(2.5, 6.5 - 0.4 * ctx.diff) / ctx.more
	local status = say(ctx, "Stay human!", "green")
	local function spawn(t: number, x: number, z: number)
		local zb = st.spawn("zombie", nil, 1)
		table.insert(zombies, { t = zb, x = x, z = z, vx = 0, vz = 0, born = t, target = nil, think = 0 })
		st.puff(A.at(x, z, 0.3), "debris", 6)
		st.puff(A.at(x, z, 0.4), "dust", 4)
	end
	local function edgeSpot(): (number, number)
		-- the far side of the room, away from everyone
		local best, bx, bz = -1, 0, 0
		for _ = 1, 6 do
			local a = rng:next() * math.pi * 2
			local x, z = math.clamp(math.cos(a) * 12, -A.lim, A.lim), math.clamp(math.sin(a) * 12, -A.lim, A.lim)
			local near = math.huge
			for _, p in A.alive() do
				near = math.min(near, dist(p.x, p.z, x, z))
			end
			if near > best then
				best, bx, bz = near, x, z
			end
		end
		return bx, bz
	end
	-- running away: of sixteen ways to run (or none), the one that keeps the most room from the nearest zombie half a
	-- second and a second on (the walls stop the player, the zombies close straight in), out of the corners
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		if t < p.think then
			return p.tx, p.tz, false
		end
		p.think = t + A.react(p)
		local seen: { Zombie } = {}
		for _, zb in zombies do
			if (p.me or t - zb.born >= (1 - p.skill) * 0.6) and t - zb.born > 0.3 then
				table.insert(seen, zb)
			end
		end
		if #seen == 0 then
			p.tx, p.tz = A.steer(p, 0, 0)
			return p.tx, p.tz, false
		end
		local L = A.lim
		local sp = A.speed * p.pace
		local zs = A.speed * pace
		local best, bx, bz = -math.huge, 0, 0
		for k = -1, 15 do
			local dx, dz = 0, 0
			if k >= 0 then
				local a = k / 16 * math.pi * 2
				dx, dz = math.cos(a), math.sin(a)
			end
			local score = math.huge
			for _, T in { 0.5, 1.1 } do
				local mx, mz = math.clamp(p.x + dx * sp * T, -L, L), math.clamp(p.z + dz * sp * T, -L, L)
				for _, zb in seen do
					score = math.min(score, dist(mx, mz, zb.x, zb.z) - zs * T)
				end
				if T > 1 then
					score -= (math.max(0, math.abs(mx) - L + 2.5) + math.max(0, math.abs(mz) - L + 2.5)) * 0.35
				end
			end
			if score > best then
				best, bx, bz = score, dx, dz
			end
		end
		p.tx, p.tz = bx, bz
		-- one about to bite: jump over it (the sooner, the faster they close in)
		local jump = false
		for _, zb in seen do
			local d = dist(p.x, p.z, zb.x, zb.z)
			local ux, uz = (zb.x - p.x) / math.max(0.1, d), (zb.z - p.z) / math.max(0.1, d)
			local closing = (p.vx - zb.vx) * ux + (p.vz - zb.vz) * uz
			local reach = 1.15 + math.max(0, closing) * (if p.me then 0.16 else 0.1 * p.skill) + 0.3
			if t - zb.born > 0.6 and d < reach then
				jump = p.me or rng:next() < p.skill
			end
		end
		return bx, bz, jump
	end
	local function step(t: number, dt: number)
		if t >= nextAt and #zombies < MAX then
			nextAt = t + gap
			local x, z = edgeSpot()
			spawn(t, x, z)
		end
		for _, zb in zombies do
			-- rising out of the ground, then after the nearest (the player a little more)
			local rise = math.clamp((t - zb.born) / 0.7, 0, 1)
			if rise >= 1 then
				if t >= zb.think then
					zb.think = t + 0.4
					local best, pick = math.huge, nil :: P?
					for _, p in A.alive() do
						local d = dist(zb.x, zb.z, p.x, p.z)
						if d < best then
							best, pick = d, p
						end
					end
					zb.target = pick
				end
				local q = zb.target
				local tx, tz = zb.x, zb.z
				if q and q.alive then
					local lead = math.min(0.5, dist(zb.x, zb.z, q.x, q.z) / (A.speed * pace)) * 0.5
					tx, tz = q.x + q.vx * lead, q.z + q.vz * lead
				end
				local dx, dz = tx - zb.x, tz - zb.z
				local d = math.max(0.01, math.sqrt(dx * dx + dz * dz))
				local sp = A.speed * pace
				-- keep apart from each other a little
				for _, o in zombies do
					if o ~= zb then
						local ox, oz = zb.x - o.x, zb.z - o.z
						local od = math.sqrt(ox * ox + oz * oz)
						if od < 1.4 and od > 0.01 then
							dx += ox / od * (1.4 - od) * 2
							dz += oz / od * (1.4 - od) * 2
						end
					end
				end
				d = math.max(0.01, math.sqrt(dx * dx + dz * dz))
				local k = math.min(1, A.grip * 0.6 * dt)
				zb.vx += (dx / d * sp - zb.vx) * k
				zb.vz += (dz / d * sp - zb.vz) * k
				zb.x = math.clamp(zb.x + zb.vx * dt, -A.lim, A.lim)
				zb.z = math.clamp(zb.z + zb.vz * dt, -A.lim, A.lim)
				-- a bite
				for _, p in A.alive() do
					if p.y < 0.6 and dist(zb.x, zb.z, p.x, p.z) < 1.15 then
						A.knock(p, t, p.x - zb.x, p.z - zb.z)
						st.puff(A.at(p.x, p.z, 1), "smoke", 4)
						A.popAt(A.head(p), if p.me then "Bitten!" else p.name .. " turned!", "green")
						if #zombies < MAX + 1 then
							spawn(t, p.x, p.z)
						end
					end
				end
			end
			local wob = math.sin(t * 6 + zb.born * 3) * 0.12
			A.place(zb.t, zb.x, zb.z, -1.6 * (1 - rise), Arena.yaw(zb.vx, zb.vz) + wob)
		end
		local humans = #A.alive()
		UIKit.setText(status, string.format("%d human%s left", humans, if humans == 1 then "" else "s"))
	end
	return wrap(A, "The zombies are coming: one bite and you turn. Run, and jump them!", step)
end

------------------------------------------------------------------ 10. sneak: creep to the door (Horror)
-- Race to the door at the back while the ghost looks away; it turns round now and then (it shudders first): anyone
-- still moving when it looks is sent back to the start. First one to the door wins.
function Games.sneak(ctx: Ctx): Micro
	local n = 1 + ctx.rivals
	local START, GOAL = 8.5, -9.2
	local starts: { { number } } = {}
	for i = 1, n do
		table.insert(starts, { -7 + (i - 1) * (14 / math.max(1, n - 1)), START })
	end
	-- the founder in the middle lane
	local mid = math.ceil(n / 2)
	starts[1], starts[mid] = starts[mid], starts[1]
	local A = Arena.new(ctx, "race", { act = "Jump", starts = starts })
	local st = ctx.stage
	local rng = ctx.rng
	-- a creep, not a run: the ghost turns round a good few times on the way
	A.speed = 2.9 * ctx.speed
	A.scoreOf = function(p: P): string
		return tostring(math.floor(p.score)) .. "%"
	end
	local ghost = st.spawn("ghost", nil, 1)
	local line = MicroModels.slab(Vector3.new(19, 0.1, 0.5), "berry_red", nil, true)
	st.adopt(line)
	A.place(line, 0, GOAL, 0.02)
	local phase = "away"
	local phaseEnd = 1.8 / ctx.speed
	local status = say(ctx, "Go!", "good")
	local function setPhase(t: number, ph: string)
		phase = ph
		if ph == "away" then
			phaseEnd = t + (1.4 + rng:next() * 2.0) / ctx.speed
			UIKit.setText(status, "Go!")
			UIKit.setTextColor(status, UIKit.color("good"))
		elseif ph == "turn" then
			phaseEnd = t + math.max(0.3, 0.62 - 0.035 * ctx.diff) / ctx.speed
			UIKit.setText(status, "It's turning...")
			UIKit.setTextColor(status, UIKit.color("yellow"))
			Audio.play("notice", { pitch = 0.8 })
			for _, p in A.players do
				-- a rival notices late, and sometimes pushes their luck
				p.data.noticeAt = t + (if p.me then 0 else (1 - p.skill) * 0.5 + (if rng:next() < (1 - p.skill) * 0.6 then 0.5 else 0))
			end
		else
			phaseEnd = t + (1.0 + rng:next() * 1.3) / ctx.speed
			UIKit.setText(status, "FREEZE!")
			UIKit.setTextColor(status, UIKit.color("bad"))
		end
	end
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		local see = phase
		if phase == "turn" and t < (p.data.noticeAt or 0) then
			see = "away"
		end
		-- the auto player creeps on through the shudder and stops just before it looks (a slippery floor sooner)
		if p.me and phase == "turn" and phaseEnd - t > (if ctx.ice then 0.55 else 0.16) then
			see = "away"
		end
		if see == "away" then
			return A.steer(p, starts[p.i][1] * 0.6, GOAL - 1)
		end
		return 0, 0, false
	end
	local function step(t: number, _dt: number)
		if t >= phaseEnd then
			setPhase(t, if phase == "away" then "turn" elseif phase == "turn" then "look" else "away")
		end
		-- the ghost: its back to them while away, a shudder, then it faces them
		local yaw = if phase == "look" then MicroStage.FACE_VIEWER + math.pi / 4 else MicroStage.FACE_AWAY + math.pi / 4
		A.place(ghost, (if phase == "turn" then math.sin(t * 50) * 0.25 else 0), -10.6, 1 + math.sin(t * 2) * 0.3, yaw)
		for _, p in A.players do
			p.score = math.clamp((START - p.z) / (START - GOAL) * 100, 0, 100)
			if p.alive and p.z <= GOAL then
				A.finishRace(p)
				return
			end
			if phase == "look" and p.stun <= 0 then
				local sp = math.sqrt(p.vx * p.vx + p.vz * p.vz)
				if sp > 1.3 or p.y > 0.05 then
					-- caught: back to the start
					st.puff(A.at(p.x, p.z, 1), "smoke", 4)
					A.popAt(A.head(p), if p.me then "Caught!" else p.name .. " caught!", "bad")
					Audio.play("sad", { volume = if p.me then 1 else 0.4 })
					p.z = START
					p.x = starts[p.i][1]
					p.vx, p.vz = 0, 0
					p.stun = 0.6
					if p.me then
						ctx.flash("purple")
					end
				end
			end
		end
	end
	return wrap(A, "Creep to the door while the ghost looks away. Freeze when it turns!", step)
end

------------------------------------------------------------------ 11. paint: claim the floor (Farming, Strategy, Simulation)
-- Every tile you step on turns your colour (until someone else steps on it); a star paints all round you. Most tiles
-- at the end wins.
local PAINT_SKIN: { [string]: { base: string, star: string, word: string } } = {
	water = { base = "wood_dark", star = "sprout", word = "plots" },
	count = { base = "paper", star = "star", word = "lands" },
	tower = { base = "steel", star = "star", word = "lots" },
}
function Games.paint(ctx: Ctx): Micro
	local skin = PAINT_SKIN[ctx.variant] or PAINT_SKIN.count
	local A = Arena.new(ctx, "score", { act = "Jump", tags = true, label = skin.word })
	local st = ctx.stage
	local rng = ctx.rng
	local N = 6
	local T = tiles(A, N, 3.15, 3.0, skin.base)
	A.lift = 0.1
	local count = N * N
	local owner: { [number]: P } = {}
	local star: Thing? = nil
	local sx, sz = 0, 0
	local starAt = 4 / ctx.more
	local function claim(i: number, p: P, quiet: boolean?)
		local was = owner[i]
		if was == p then
			return
		end
		if was then
			was.score -= 1
		end
		owner[i] = p
		p.score += 1
		T.color(i, p.color)
		if not quiet then
			local x, z = T.center(i)
			st.puff(A.at(x, z, 0.3), "dust", 2, p.color)
			if p.me then
				Audio.play("pop", { pitch = 1.4 + rng:next() * 0.3, volume = 0.5 })
			end
		end
	end
	A.brain = function(p: P, t: number, _dt: number): (number, number, boolean)
		if t >= p.think then
			p.think = t + A.react(p)
			local best, bi = -math.huge, 0
			local noisy = not p.me and rng:next() < (1 - p.skill) * 0.4
			for i = 1, count do
				local o = owner[i]
				if o ~= p then
					local x, z = T.center(i)
					local v = (if o then 1.4 else 1) / (dist(p.x, p.z, x, z) + 1)
					if p.me then
						-- far from the others (it stays painted), from the leader most
						local near = math.huge
						for _, q in A.others(p) do
							near = math.min(near, dist(q.x, q.z, x, z))
						end
						v *= math.clamp(near / 5, 0.25, 1) * (if o and o.score >= p.score then 1.3 else 1)
					end
					if noisy then
						v = rng:next()
					end
					if v > best then
						best, bi = v, i
					end
				end
			end
			-- the star is worth a detour
			if star and dist(p.x, p.z, sx, sz) < (if p.me then 14 else 7) and (p.me or rng:next() < p.skill) then
				p.tx, p.tz = sx, sz
			elseif bi > 0 then
				p.tx, p.tz = T.center(bi)
			end
		end
		return A.steer(p, p.tx, p.tz)
	end
	local function step(t: number, dt: number)
		for _, p in A.players do
			if p.alive and p.y < 0.3 then
				claim(T.index(p.x, p.z), p)
			end
		end
		if star == nil and t >= starAt then
			sx, sz = T.center(rng:int(1, count))
			star = st.spawn(skin.star, nil, 0.6)
			Audio.play("sparkle", { volume = 0.6 })
		end
		local s = star
		if s then
			A.place(s, sx, sz, 0.6 + math.sin(t * 4) * 0.25, t * 2)
			if every(t, dt, 5) then
				st.puff(A.at(sx, sz, 1), "twinkle", 1)
			end
			for _, p in A.players do
				if p.alive and dist(p.x, p.z, sx, sz) < 1.3 then
					-- everything round them turns their colour
					local c = T.index(sx, sz)
					local r0, c0 = (c - 1) // N, (c - 1) % N
					for dr = -1, 1 do
						for dc = -1, 1 do
							local r, cc = r0 + dr, c0 + dc
							if r >= 0 and r < N and cc >= 0 and cc < N then
								claim(r * N + cc + 1, p, true)
							end
						end
					end
					st.puff(A.at(sx, sz, 0.8), "confetti", 12)
					A.popAt(A.head(p), "Splash!", p.color)
					Audio.play("combo", { volume = if p.me then 1 else 0.4 })
					st.remove(s)
					star = nil
					starAt = t + (5 + rng:next() * 2) / ctx.more
					break
				end
			end
		end
		T.flush()
	end
	return wrap(A, "Step on tiles to turn them your colour. Most tiles wins!", step)
end

return Games
