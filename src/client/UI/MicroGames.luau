--!strict
-- The microgames (GAME_DESIGN 5; docs/ARCHITECTURE.md 10.8): twelve engines, each played by one or more ideas in
-- their own theme (Data/Ideas micro + variant), WarioWare style: a one-word order, a few seconds, win or lose. An
-- engine gets the play area (its scene, UI/MicroScenes, already drawn under it) and a context (the difficulty 1..8
-- from the idea's rarity, the Turbo speed, Tiny, an Rng seeded by the server) and calls ctx.win() or ctx.lose(); one
-- that is `survive` wins when the clock runs out first. MicroUI runs the clock, the effects (pops, bursts, floats,
-- flashes, shakes) and the modifiers' screen effects (shake, glitch, dark).
--
-- Pixel art (GAME_DESIGN 2): every thing is a sprite from UI/ArtData at its own size (PixelSprites.image / anim), at
-- whole UI px; Tiny swaps in the thing's small sprite ("coin" -> "coin_t", "icon_" -> "mini_"), never a scaled one.
-- Things animate by frames (a run cycle, a spinning coin, a wiggling fish) and flash white when hit.
--
-- Every button a sim can press has a name (Pad_<key>, Hole_<i>, Opt_<i>, Fruit_<i>); `auto` makes one right move (the
-- sims' player).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)

export type Ctx = {
	area: Frame,
	w: number,
	h: number,
	rng: Types.Rng,
	diff: number, -- 1 .. Tuning.DiffMax
	speed: number, -- 1, or Tuning.TurboSpeed
	tiny: boolean, -- Tiny: the targets are their small sprites
	variant: string,
	pop: (x: number, y: number, text: string, color: Color3) -> (),
	burst: (x: number, y: number, colors: { string }, n: number?) -> (), -- 1 px bits fly out and fall
	float: (g: GuiObject, vx: number, vy: number, life: number, gravity: number?) -> (), -- moves it, then destroys it
	flash: (color: string) -> (), -- the area flashes for a moment
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
	pace: number?, -- how fast the scene scrolls (px/s: Racing's road)
	auto: () -> (),
}

local Games = {}

------------------------------------------------------------------ helpers
local function snap(v: number): number
	return math.floor(v + 0.5)
end

-- A thing's sprite: its small one when Tiny ("cone" -> "cone_t"), else its own.
local function pick(ctx: Ctx, base: string): string
	if ctx.tiny and PixelSprites.has(base .. "_t") then
		return base .. "_t"
	end
	return base
end

-- A thing's frames: base_1 .. base_n, or its one small sprite when Tiny.
local function framesOf(ctx: Ctx, base: string, n: number): { string }
	if ctx.tiny and PixelSprites.has(base .. "_t") then
		return { base .. "_t" }
	end
	local out = {}
	for i = 1, n do
		out[i] = base .. "_" .. i
	end
	return out
end

-- An idea's icon: 16 px, or its 11 px one when Tiny.
local function iconOf(ctx: Ctx, id: string): string
	return (if ctx.tiny then "mini_" else "icon_") .. id
end

local function img(parent: Instance, name: string, x: number, y: number, z: number?): GuiObject
	return PixelSprites.image(parent, name, UDim2.fromOffset(snap(x), snap(y)), z or 9)
end

local function anim(parent: Instance, names: { string }, x: number, y: number, z: number?): PixelSprites.Anim
	return PixelSprites.anim(parent, names, UDim2.fromOffset(snap(x), snap(y)), z or 9)
end

local function box(parent: Instance, w: number, h: number, x: number, y: number, color: string, z: number?): Frame
	return UIKit.rect(parent, UDim2.fromOffset(math.max(0, snap(w)), math.max(0, snap(h))), UDim2.fromOffset(snap(x), snap(y)), UIKit.color(color), z or 8)
end

local WHITE = Color3.new(1, 1, 1)
local INK = UIKit.color("ink")

-- A block with a 1 px ink outline, a lighter top row and a darker bottom row (the meter's zone, the stack's floors).
local function block(parent: Instance, w: number, h: number, x: number, y: number, fill: Color3, z: number): Frame
	local f = UIKit.rect(parent, UDim2.fromOffset(w, h), UDim2.fromOffset(snap(x), snap(y)), INK, z)
	f.Name = "Block"
	local inner = UIKit.rect(f, UDim2.fromOffset(math.max(0, w - 2), math.max(0, h - 2)), UDim2.fromOffset(1, 1), fill, z)
	inner.Name = "Fill"
	if h >= 4 then
		UIKit.rect(f, UDim2.fromOffset(math.max(0, w - 2), 1), UDim2.fromOffset(1, 1), fill:Lerp(WHITE, 0.4), z).Name = "Hi"
	end
	if h >= 6 then
		UIKit.rect(f, UDim2.fromOffset(math.max(0, w - 2), 1), UDim2.fromOffset(1, h - 2), fill:Lerp(INK, 0.3), z).Name = "Lo"
	end
	return f
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

-- A touch pad along the area's bottom (or anywhere): it presses `key`.
local function pad(ctx: Ctx, text: string, key: string, x: number, y: number, w: number, h: number, color: string?): TextButton
	local b = UIKit.button(ctx.area, text, UDim2.fromOffset(w, h), UDim2.fromOffset(snap(x), snap(y)), function()
		ctx.press(key)
	end, { name = "Pad_" .. key, color = UIKit.color(color or "plate_light") })
	b.ZIndex = 10
	return b
end

-- Arrow pads: each shows its 7 px arrow on the plate (it sinks with the plate when pressed).
local function arrowPads(ctx: Ctx, keys: { string })
	local pw, ph = 26, 16
	local total = #keys * (pw + 3) - 3
	for i, k in keys do
		local b = pad(ctx, "", k, (ctx.w - total) / 2 + (i - 1) * (pw + 3), ctx.h - ph, pw, ph)
		local plate = b:FindFirstChild("Plate") or b
		img(plate, "arrow_" .. k .. "_t", math.floor((pw - 7) / 2), math.floor((ph - 7) / 2), 4)
	end
end

-- A one-line hint at the top of the area.
local function say(ctx: Ctx, text: string, color: string?): TextLabel
	return UIKit.text(ctx.area, text, UDim2.fromOffset(ctx.w, 10), UDim2.fromOffset(0, 1), { x = "center", color = UIKit.color(color or "text"), kind = "outline", z = 12, name = "Say" })
end

-- A button with nothing drawn on it (a hole, a pet, a fruit): the sprite goes inside.
local function hitbox(ctx: Ctx, name: string, w: number, h: number, x: number, y: number, z: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.BackgroundTransparency = 1
	b.BorderSizePixel = 0
	b.AutoButtonColor = false
	b.Size = UDim2.fromOffset(w, h)
	b.Position = UDim2.fromOffset(snap(x), snap(y))
	b.ZIndex = z
	b.Parent = ctx.area
	return b
end

------------------------------------------------------------------ lanes: dodge and catch
-- A row of lanes along the bottom (dotted dividers) with a mover the arrows (or the pads) step from lane to lane;
-- things come down the lanes from above the area.
type Faller = { a: PixelSprites.Anim, lane: number, y: number, w: number, h: number, good: boolean, gone: boolean }
type Lanes = {
	lw: number,
	x0: number,
	my: number,
	mw: number,
	mh: number,
	n: number,
	me: PixelSprites.Anim,
	lane: () -> number,
	move: (d: number) -> (),
	xOf: (l: number, w: number) -> number,
	scroll: (t: number, pace: number) -> (),
	bump: () -> (),
}
local function lanes(ctx: Ctx, n: number, mover: { string }, within: number?): Lanes
	local avail = within or ctx.w
	local lw = math.min(36, math.floor(avail / (if within then n else n + 1)))
	local x0 = math.floor((ctx.w - lw * n) / 2)
	local dashes: { Frame } = {}
	for i = 1, n - 1 do
		local x = x0 + i * lw
		for y = -8, ctx.h - 20, 8 do
			local d = box(ctx.area, 1, 3, x, y, "white", 6)
			d.BackgroundTransparency = 0.55
			d.Name = "Divider"
			table.insert(dashes, d)
		end
	end
	local mw, mh = PixelSprites.size(mover[1])
	local lane = math.ceil(n / 2)
	local my = ctx.h - 19 - mh
	local function xOf(l: number, w: number): number
		return x0 + (l - 1) * lw + math.floor((lw - w) / 2)
	end
	local me = anim(ctx.area, mover, xOf(lane, mw), my, 10)
	arrowPads(ctx, { "left", "right" })
	return {
		lw = lw,
		x0 = x0,
		my = my,
		mw = mw,
		mh = mh,
		n = n,
		me = me,
		lane = function(): number
			return lane
		end,
		move = function(d: number)
			local nl = math.clamp(lane + d, 1, n)
			if nl ~= lane then
				lane = nl
				UIKit.tween(me.f, 0.06, { Position = UDim2.fromOffset(xOf(lane, mw), my) })
			end
		end,
		xOf = xOf,
		scroll = function(t: number, pace: number)
			local off = math.floor(t * pace) % 8
			local per = #dashes // math.max(1, n - 1)
			for i, d in dashes do
				local row = (i - 1) % math.max(1, per)
				d.Position = UDim2.fromOffset(d.Position.X.Offset, -8 + row * 8 + off)
			end
		end,
		bump = function()
			me.moveTo(xOf(lane, mw), my + 1)
			task.delay(0.06, function()
				if me.f.Parent then
					me.moveTo(xOf(lane, mw), my)
				end
			end)
		end,
	}
end

------------------------------------------------------------------ 1. dodge (Action "Dodge!", Racing "Steer!")
function Games.dodge(ctx: Ctx): Micro
	local race = ctx.variant == "race"
	local n = if ctx.diff >= 7 then 5 elseif ctx.diff >= 4 then 4 else 3
	local L = lanes(ctx, n, if race then { pick(ctx, "car") } else framesOf(ctx, "hero", 2), if race then math.floor(ctx.w * 0.62) else nil)
	local thing = pick(ctx, if race then "cone" else "block")
	local tw, th = PixelSprites.size(thing)
	local items: { Faller } = {}
	local nextAt = 0.4
	local fall = (46 + 9 * ctx.diff) * ctx.speed
	local every = math.max(0.32, 0.8 - 0.06 * ctx.diff) / ctx.speed
	local dead = false
	local spawnY = -th
	local band = spawnY + 20 + th + L.mh
	say(ctx, if race then "Steer clear of the cones!" else "Dodge the blocks!")
	return {
		survive = true,
		pace = if race then fall else nil,
		update = function(t: number, dt: number)
			if dead then
				return
			end
			L.me.set(math.floor(t * 8) + 1)
			if race then
				L.scroll(t, fall)
			end
			if t >= nextAt then
				nextAt = t + every * (0.7 + 0.6 * ctx.rng:next())
				-- never a wall: a lane stays open in every band of the screen
				local busy: { [number]: boolean } = {}
				local nBusy = 0
				for _, it in items do
					if not it.gone and it.y < band and not busy[it.lane] then
						busy[it.lane] = true
						nBusy += 1
					end
				end
				local l = ctx.rng:int(1, n)
				if nBusy < n - 1 or busy[l] then
					local a = anim(ctx.area, { thing }, L.xOf(l, tw), spawnY, 9)
					table.insert(items, { a = a, lane = l, y = spawnY, w = tw, h = th, good = false, gone = false })
				end
			end
			for _, it in items do
				if not it.gone then
					it.y += fall * dt
					it.a.moveTo(L.xOf(it.lane, tw), it.y)
					if it.lane == L.lane() and it.y + th > L.my + 2 and it.y < L.my + L.mh - 2 then
						dead = true
						L.me.flash(0.3)
						it.a.flash(0.3)
						ctx.burst(L.xOf(it.lane, 0), L.my, { "white", "accent", "bad" }, 14)
						ctx.shake()
						ctx.lose()
						return
					end
					if it.y > ctx.h - 18 then
						it.gone = true
						it.a.f:Destroy()
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
		auto = function()
			-- how far the nearest thing coming down a lane still is (huge: none)
			local function gap(l: number): number
				local g = math.huge
				for _, it in items do
					if not it.gone and it.lane == l and it.y < L.my + L.mh then
						g = math.min(g, L.my - (it.y + th))
					end
				end
				return g
			end
			local here = L.lane()
			if gap(here) > 70 then
				return
			end
			local best, bestGap = here, gap(here)
			for l = 1, n do
				local g = gap(l)
				-- the path there must be clear right now
				local clear = true
				local step = if l > here then 1 else -1
				for k = here + step, l, step do
					if l ~= here and gap(k) < 4 then
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
-- A needle swings along a meter; press while it is in the green. Each hit plays the theme: the pancake flips, the
-- ball flies into the goal, the hero slashes the slime.
function Games.timing(ctx: Ctx): Micro
	local v = ctx.variant
	local need = if ctx.diff >= 7 then 3 elseif ctx.diff >= 4 then 2 else 1
	local bw = math.min(200, ctx.w - 40)
	local bx, by = math.floor((ctx.w - bw) / 2), 15
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
	local cx = math.floor(ctx.w / 2)
	-- the stage
	local hero: PixelSprites.Anim? = nil
	local thing: PixelSprites.Anim? = nil
	local thingHome = Vector2.zero
	local foe: PixelSprites.Anim? = nil
	local flames: { Frame } = {}
	if v == "flip" then
		-- the pan on the stove's grate over a flickering flame
		local pw, ph = PixelSprites.size("pan")
		local panY = ctx.h - 25 - ph - 4
		img(ctx.area, "pan", cx - math.floor(pw / 2) + 3, panY, 9)
		box(ctx.area, 22, 1, cx - 11, ctx.h - 26, "steel_dark", 8)
		box(ctx.area, 1, 4, cx - 8, ctx.h - 29, "ink", 8)
		box(ctx.area, 1, 4, cx + 7, ctx.h - 29, "ink", 8)
		for i = 0, 4 do
			local fl = box(ctx.area, 1, 2, cx - 5 + i * 2 + (if i >= 2 then 1 else 0), ctx.h - 28, if i % 2 == 0 then "orange" else "yellow", 8)
			fl.Name = "Flame"
			table.insert(flames, fl)
		end
		local cw = PixelSprites.size("pancake")
		thingHome = Vector2.new(cx - math.floor(cw / 2), panY - 3)
		thing = anim(ctx.area, { "pancake" }, thingHome.X, thingHome.Y, 10)
	elseif v == "kick" then
		local gw = PixelSprites.size("goal")
		img(ctx.area, "goal", cx - math.floor(gw / 2), 30, 8)
		hero = anim(ctx.area, { "hero_1", "hero_2" }, cx - 34, ctx.h - 36, 10)
		thingHome = Vector2.new(cx - 20, ctx.h - 30)
		thing = anim(ctx.area, { "ball" }, thingHome.X, thingHome.Y, 11)
	else
		hero = anim(ctx.area, { "hero_1", "hero_2" }, cx - 44, ctx.h - 36, 10)
		local sw, sh = PixelSprites.size("slime_1")
		foe = anim(ctx.area, { "slime_1", "slime_2" }, cx + 24, ctx.h - 20 - sh, 10)
		img(ctx.area, "icon_rpg", cx - 34, ctx.h - 38, 11)
		local _ = sw
	end
	local count = say(ctx, string.format("Hit the green: 0/%d", need))
	local function placeZone()
		zx = ctx.rng:int(0, bw - zoneW)
		zone.Position = UDim2.fromOffset(bx + zx, by)
	end
	placeZone()
	local done = false
	local function back(a: PixelSprites.Anim, home: Vector2, after: number)
		task.delay(after, function()
			if a.f.Parent then
				UIKit.tween(a.f, 0.14, { Position = UDim2.fromOffset(home.X, home.Y) })
			end
		end)
	end
	local function hitFx()
		if v == "flip" and thing then
			local th = thing :: PixelSprites.Anim
			UIKit.tween(th.f, 0.14, { Position = UDim2.fromOffset(thingHome.X, thingHome.Y - 30) })
			back(th, thingHome, 0.16)
			ctx.burst(thingHome.X + 9, thingHome.Y, { "yellow", "white", "orange" }, 8)
		elseif v == "kick" and thing then
			local th = thing :: PixelSprites.Anim
			UIKit.tween(th.f, 0.16, { Position = UDim2.fromOffset(cx - 5 + ctx.rng:int(-12, 12), 36 + ctx.rng:int(0, 6)) })
			back(th, thingHome, 0.4)
			if hero then
				(hero :: PixelSprites.Anim).set(2)
			end
			task.delay(0.16, function()
				ctx.burst(cx, 42, { "white", "good", "yellow" }, 12)
				if hero then
					(hero :: PixelSprites.Anim).set(1)
				end
			end)
		elseif foe and hero then
			local fo, he = foe :: PixelSprites.Anim, hero :: PixelSprites.Anim
			local home = Vector2.new(cx - 44, ctx.h - 36)
			UIKit.tween(he.f, 0.06, { Position = UDim2.fromOffset(cx + 6, ctx.h - 36) })
			back(he, home, 0.1)
			fo.flash(0.12)
			ctx.burst(cx + 33, ctx.h - 28, { "green", "white", "leaf" }, 10)
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
				if foe then
					local fo = foe :: PixelSprites.Anim
					task.delay(0.12, function()
						if fo.f.Parent then
							ctx.burst(cx + 33, ctx.h - 28, { "green", "leaf", "white" }, 18)
							fo.f.Visible = false
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
			if v == "flip" and thing then
				UIKit.tween((thing :: PixelSprites.Anim).f, 0.25, { Position = UDim2.fromOffset(thingHome.X + 34, ctx.h - 20) })
			elseif v == "kick" and thing then
				UIKit.tween((thing :: PixelSprites.Anim).f, 0.25, { Position = UDim2.fromOffset(cx + 50, 26) })
			elseif hero then
				(hero :: PixelSprites.Anim).flash(0.25)
			end
			ctx.shake()
			ctx.lose()
		end
	end
	pad(ctx, "Go!", "go", ctx.w / 2 - 30, ctx.h - 16, 60, 16, "accent")
	return {
		update = function(t: number, dt: number)
			if done then
				return
			end
			if foe then
				(foe :: PixelSprites.Anim).set(math.floor(t * 3) + 1)
			end
			for i, fl in flames do
				local fh = 1 + (math.floor(t * 14) + i * 2) % 3
				fl.Size = UDim2.fromOffset(1, fh)
				fl.Position = UDim2.fromOffset(fl.Position.X.Offset, ctx.h - 26 - fh)
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
		auto = function()
			if pos >= zx + 1 and pos <= zx + zoneW - 1 then
				press()
			end
		end,
	}
end

------------------------------------------------------------------ 3. mash (Animals "Pet!")
function Games.mash(ctx: Ctx): Micro
	local need = 8 + 2 * ctx.diff
	local n = 0
	local names = if ctx.tiny then { "icon_animals" } else { "cat_1", "cat_2" }
	local cw, ch = PixelSprites.size(names[1])
	local cx, cy = math.floor((ctx.w - cw) / 2), math.floor((ctx.h - ch) / 2) + 2
	-- a soft shadow under the pet
	local sh1 = box(ctx.area, cw - 6, 1, cx + 3, cy + ch, "ink", 8)
	sh1.BackgroundTransparency = 0.6
	local sh2 = box(ctx.area, cw - 12, 1, cx + 6, cy + ch + 1, "ink", 8)
	sh2.BackgroundTransparency = 0.75
	local pet = hitbox(ctx, "Pad_go", cw + 8, ch + 8, cx - 4, cy - 4, 9)
	local cat = anim(pet, names, 4, 4, 10)
	pet.Activated:Connect(function()
		ctx.press("go")
	end)
	local setBar = meter(ctx.area, math.floor(ctx.w / 2 - 54), 15, 120, 6, "pink", 10)
	setBar(0)
	img(ctx.area, "heart", math.floor(ctx.w / 2 - 54) - 14, 12, 10)
	local label = say(ctx, string.format("Pet it! 0/%d", need))
	local done = false
	local now = 0
	local happyUntil = 0
	local squashUntil = 0
	local function press()
		if done then
			return
		end
		n += 1
		setBar(n / need)
		UIKit.setText(label, string.format("Pet it! %d/%d", n, need))
		Audio.play("pop", { volume = 0.6, pitch = 1 + (n % 5) * 0.06 })
		happyUntil = now + 0.3
		squashUntil = now + 0.07
		cat.set(2)
		cat.moveTo(4, 5)
		local hx = cx + ctx.rng:int(0, math.max(0, cw - 11))
		local heart = img(ctx.area, "heart", hx, cy - 4, 13)
		ctx.float(heart, (ctx.rng:next() - 0.5) * 16, -28, 0.7)
		ctx.burst(hx + 5, cy, { "pink", "white" }, 4)
		if n >= need then
			done = true
			ctx.burst(cx + cw / 2, cy + ch / 2, { "pink", "white", "berry_red" }, 18)
			ctx.win()
		end
	end
	return {
		update = function(t: number, _dt: number)
			now = t
			cat.set(if t < happyUntil or done then 2 else 1)
			-- it breathes: one pixel up and down
			local breath = if math.floor(t * 2) % 2 == 0 then 0 else 1
			cat.moveTo(4, 4 + (if t < squashUntil then 1 else breath))
		end,
		key = function(_k: string)
			press()
		end,
		auto = function()
			press()
		end,
	}
end

------------------------------------------------------------------ 4. whack (Space "Shoot!", Farming "Water!", Zombies "Whack!")
-- Things pop up out of holes: tap the right ones (not the decoys).
function Games.whack(ctx: Ctx): Micro
	local cols = if ctx.diff >= 3 then 4 else 3
	local rows = if ctx.diff >= 6 then 3 else 2
	local need = 4 + ctx.diff
	local v = ctx.variant
	-- Space's craters, the graveyard's stone-rimmed holes, the field's soil
	local holeName = "hole" .. (if ctx.tiny then "_t" else "") .. (if v == "space" then "_crater" elseif v == "zombie" then "_grave" else "")
	local hw, hh = PixelSprites.size(holeName)
	local targetNames = if v == "space" then framesOf(ctx, "alien", 2) elseif v == "water" then { pick(ctx, "sprout") } else { iconOf(ctx, "zombies") }
	local decoyNames: { string }? = if v == "space" then { iconOf(ctx, "space") } elseif v == "zombie" then { pick(ctx, "kid") } else nil
	local afterName = if v == "water" then pick(ctx, "flower") else nil
	local colors = if v == "space" then { "green", "white", "yellow" } elseif v == "water" then { "blue", "white" } else { "green", "leaf", "white" }
	local cw, ch = 32, 30
	local gx = math.floor((ctx.w - cols * (cw + 4) + 4) / 2)
	local gy = 12 + math.floor((ctx.h - 12 - rows * (ch + 2)) / 2)
	local clipH = ch - math.ceil(hh / 2)
	type Popper = { a: PixelSprites.Anim, w: number, h: number }
	type Hole = { b: TextButton, t: Popper, d: Popper?, untilT: number, decoy: boolean, up: Popper? }
	local holes: { Hole } = {}
	local hits = 0
	local now = 0
	local nextAt = 0.2
	local life = math.max(0.45, 1.05 - 0.07 * ctx.diff) / ctx.speed
	local every = math.max(0.25, 0.6 - 0.04 * ctx.diff) / ctx.speed
	local done = false
	local verb = if v == "water" then "Water the dry ones:" elseif v == "space" then "Shoot the aliens:" else "Whack the zombies:"
	local label = say(ctx, string.format("%s 0/%d", verb, need))
	local function rise(p: Popper, up: boolean)
		local y = if up then clipH - p.h + 1 else clipH
		UIKit.tween(p.a.f, 0.07, { Position = UDim2.fromOffset(math.floor((cw - p.w) / 2), y) })
	end
	local function sink(hole: Hole)
		if hole.up then
			rise(hole.up :: Popper, false)
		end
		hole.up = nil
		hole.untilT = 0
	end
	local function hit(i: number)
		local hole = holes[i]
		if done or hole.untilT <= now or hole.up == nil then
			return
		end
		local p = hole.up :: Popper
		local px, py = hole.b.Position.X.Offset + cw / 2, hole.b.Position.Y.Offset + clipH - p.h / 2
		if hole.decoy then
			done = true
			p.a.flash(0.3)
			ctx.shake()
			ctx.burst(px, py, { "bad", "white" }, 10)
			ctx.pop(px, hole.b.Position.Y.Offset, "Oops!", UIKit.color("bad"))
			ctx.lose()
			return
		end
		hits += 1
		Audio.play("squish")
		p.a.flash(0.12)
		ctx.burst(px, py, colors, 9)
		ctx.pop(px, hole.b.Position.Y.Offset, "+1", UIKit.color("good"))
		UIKit.setText(label, string.format("%s %d/%d", verb, hits, need))
		hole.untilT = 0
		if afterName then
			-- the sprout blooms for a moment
			local fw, fh = PixelSprites.size(afterName)
			p.a.f.Visible = false
			local clip = hole.b:FindFirstChild("Clip") :: Frame
			local fl = img(clip, afterName, math.floor((cw - fw) / 2), clipH - fh + 1, 11)
			task.delay(0.35, function()
				fl:Destroy()
				p.a.f.Visible = true
				p.a.f.Position = UDim2.fromOffset(math.floor((cw - p.w) / 2), clipH)
			end)
			hole.up = nil
		else
			local hp = hole
			task.delay(0.1, function()
				if hp.untilT == 0 then
					sink(hp)
				end
			end)
		end
		if hits >= need then
			done = true
			ctx.win()
		end
	end
	local function popper(clip: Frame, names: { string }): Popper
		local w, h = PixelSprites.size(names[1])
		return { a = anim(clip, names, math.floor((cw - w) / 2), clipH, 10), w = w, h = h }
	end
	for i = 1, cols * rows do
		local c, r = (i - 1) % cols, (i - 1) // cols
		local b = hitbox(ctx, "Hole_" .. i, cw, ch, gx + c * (cw + 4), gy + r * (ch + 2), 8)
		img(b, holeName, math.floor((cw - hw) / 2), ch - hh, 8)
		local clip = Instance.new("Frame")
		clip.Name = "Clip"
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		clip.Size = UDim2.fromOffset(cw, clipH)
		clip.ZIndex = 9
		clip.Active = false
		clip.Parent = b
		local t = popper(clip, targetNames)
		local d = if decoyNames then popper(clip, decoyNames :: { string }) else nil
		b.Activated:Connect(function()
			hit(i)
		end)
		holes[i] = { b = b, t = t, d = d, untilT = 0, decoy = false, up = nil }
	end
	return {
		update = function(t: number, _dt: number)
			now = t
			for _, hole in holes do
				hole.t.a.set(math.floor(t * 6) + 1)
				if hole.untilT > 0 and hole.untilT <= t then
					sink(hole)
				end
			end
			if t >= nextAt and not done then
				nextAt = t + every
				local free = {}
				for i, hole in holes do
					if hole.untilT <= t and hole.up == nil then
						table.insert(free, i)
					end
				end
				if #free > 0 then
					local hole = holes[free[ctx.rng:int(1, #free)]]
					hole.decoy = hole.d ~= nil and ctx.diff >= 4 and ctx.rng:chance(0.25)
					hole.untilT = t + life
					local p = if hole.decoy and hole.d then hole.d :: Popper else hole.t
					hole.up = p
					rise(p, true)
				end
			end
		end,
		key = function(_k: string) end,
		auto = function()
			for i, hole in holes do
				if hole.untilT > now and not hole.decoy and hole.up ~= nil then
					hit(i)
					return
				end
			end
		end,
	}
end

------------------------------------------------------------------ 5. pick (Puzzle "Match!", School "Answer!", Strategy "Count!", Detectives "Spot it!")
function Games.pick(ctx: Ctx): Micro
	local variant = ctx.variant
	local n = if ctx.diff >= 7 then 6 elseif ctx.diff >= 5 then 5 elseif ctx.diff >= 3 then 4 else 3
	local right = 1
	local done = false
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
			ctx.burst(x, y, { "good", "white", "yellow" }, 12)
			ctx.win()
		else
			mark(i, false)
			mark(right, true)
			ctx.burst(x, y, { "bad", "white" }, 8)
			ctx.shake()
			ctx.lose()
		end
	end
	type Mover = { f: GuiObject, x: number, y: number, vx: number, vy: number }
	local movers: { Mover } = {}
	local bobs: { { f: GuiObject, x: number, y: number } } = {}
	if variant == "spot" then
		-- a grid of one icon, one of them in other colours: tap it
		local cols = if ctx.diff >= 6 then 6 elseif ctx.diff >= 3 then 5 else 4
		local rows = if ctx.diff >= 6 then 4 else 3
		local base = iconOf(ctx, ({ "detectives", "pirates", "horror", "robots" })[ctx.rng:int(1, 4)])
		local iw, ih = PixelSprites.size(base)
		right = ctx.rng:int(1, cols * rows)
		local cell = iw + 8
		local gx = math.floor((ctx.w - cols * cell) / 2) + 1
		local gy = 12 + math.floor((ctx.h - 12 - rows * cell) / 2)
		local plates: { Frame } = {}
		for i = 1, cols * rows do
			local c, r = (i - 1) % cols, (i - 1) // cols
			local b = hitbox(ctx, "Opt_" .. i, cell - 2, cell - 2, gx + c * cell, gy + r * cell, 8)
			b.AutoButtonColor = true
			local pl = UIKit.plate(b, UDim2.fromScale(1, 1), nil, UIKit.color("paper"), 0, 1)
			pl.ZIndex = 8
			plates[i] = pl
			local ix, iy = math.floor((cell - 2 - iw) / 2), math.floor((cell - 2 - ih) / 2)
			local im = img(b, if i == right then base .. "_alt" else base, ix, iy, 9)
			table.insert(bobs, { f = im, x = ix, y = iy })
			b.Activated:Connect(function()
				choose(i)
			end)
		end
		mark = function(i: number, good: boolean)
			UIKit.setPlate(plates[i], UIKit.color(if good then "good" else "bad"))
		end
		where = function(i: number): (number, number)
			local c, r = (i - 1) % cols, (i - 1) // cols
			return gx + c * cell + cell / 2, gy + r * cell + cell / 2
		end
		say(ctx, "Spot the odd one out!")
		return {
			update = function(t: number, _dt: number)
				-- a ripple runs over the grid
				for i, bo in bobs do
					local up = if math.floor(t * 4 - i * 0.35) % 6 == 0 then 1 else 0
					bo.f.Position = UDim2.fromOffset(bo.x, bo.y - up)
				end
			end,
			key = function(_k: string) end,
			auto = function()
				choose(right)
			end,
		}
	end
	-- a question at the top, n options along the bottom (keys 1..n)
	local labels: { string } = {}
	local icons: { string } = {}
	if variant == "match" then
		local pool = { "action", "puzzle", "animals", "space", "cooking", "school", "racing", "pirates", "ocean", "rpg", "fantasy", "robots", "ninjas", "zombies", "horror", "music" }
		for i = #pool, 2, -1 do
			local j = ctx.rng:int(1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end
		right = ctx.rng:int(1, n)
		for i = 1, n do
			icons[i] = pool[i]
		end
		say(ctx, "Which one matches?")
		local card = UIKit.plate(ctx.area, UDim2.fromOffset(26, 26), UDim2.fromOffset(math.floor(ctx.w / 2) - 13, 13), UIKit.color("paper"), 0, 2)
		card.ZIndex = 8
		local ink = UIKit.plate(ctx.area, UDim2.fromOffset(28, 28), UDim2.fromOffset(math.floor(ctx.w / 2) - 14, 12), INK, 0, 2)
		ink.ZIndex = 7
		local im = img(card, "icon_" .. icons[right], 5, 5, 9)
		table.insert(bobs, { f = im, x = 5, y = 5 })
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
			UIKit.text(ctx.area, q, UDim2.fromOffset(ctx.w, 18), UDim2.fromOffset(0, 22), { x = "center", face = "big", color = WHITE, z = 10, name = "Question" })
		else
			-- count: soldiers spread over the field, never on top of each other (marching from difficulty 5)
			answer = ctx.rng:int(3, 5 + ctx.diff)
			q = "How many soldiers?"
			local sn = pick(ctx, "soldier")
			local sw, sh = PixelSprites.size(sn)
			local cellW, cellH = sw + 6, sh + 4
			local fx0, fy0 = 8, 13
			local gcols = math.max(1, math.floor((ctx.w - 16) / cellW))
			local grows = math.max(1, math.floor((ctx.h - 34 - fy0) / cellH))
			local cells: { number } = {}
			for i = 1, gcols * grows do
				cells[i] = i
			end
			for i = #cells, 2, -1 do
				local j = ctx.rng:int(1, i)
				cells[i], cells[j] = cells[j], cells[i]
			end
			for k = 1, math.min(answer, #cells) do
				local c, r = (cells[k] - 1) % gcols, (cells[k] - 1) // gcols
				local x, y = fx0 + c * cellW + ctx.rng:int(0, 4), fy0 + r * cellH + ctx.rng:int(0, 2)
				local f = img(ctx.area, sn, x, y, 9)
				if ctx.diff >= 5 then
					table.insert(movers, { f = f, x = x, y = y, vx = (ctx.rng:next() - 0.5) * 50, vy = (ctx.rng:next() - 0.5) * 30 })
				else
					table.insert(bobs, { f = f, x = x, y = y })
				end
			end
			answer = math.min(answer, #cells)
		end
		say(ctx, if variant == "answer" then "Answer it!" else q)
		right = ctx.rng:int(1, n)
		for i = 1, n do
			labels[i] = tostring(math.max(0, answer + (i - right) * (if variant == "count" then 1 else ctx.rng:int(1, 3))))
		end
		-- no two options the same
		for i = 1, n do
			for j = 1, i - 1 do
				if labels[i] == labels[j] then
					labels[i] = tostring(tonumber(labels[i]) :: number + 10 + i)
				end
			end
		end
	end
	local oh = if variant == "match" then (if ctx.tiny then 22 else 28) else 18
	local ow = math.min(36, math.floor((ctx.w - 8) / n) - 4)
	local total = n * (ow + 4) - 4
	local buttons: { TextButton } = {}
	for i = 1, n do
		local b = UIKit.button(ctx.area, labels[i] or "", UDim2.fromOffset(ow, oh), UDim2.fromOffset(math.floor((ctx.w - total) / 2) + (i - 1) * (ow + 4), ctx.h - oh), function()
			choose(i)
		end, { name = "Opt_" .. i, color = UIKit.color("plate_light"), face = if variant == "match" then nil else "big" })
		b.ZIndex = 10
		buttons[i] = b
		if icons[i] then
			local name = iconOf(ctx, icons[i])
			local iw, ih = PixelSprites.size(name)
			img(b:FindFirstChild("Plate") or b, name, math.floor((ow - iw) / 2), math.floor((oh - ih) / 2), 4)
		end
	end
	mark = function(i: number, good: boolean)
		UIKit.setButtonColor(buttons[i], UIKit.color(if good then "good" else "bad"))
	end
	where = function(i: number): (number, number)
		local b = buttons[i]
		return b.Position.X.Offset + ow / 2, b.Position.Y.Offset + oh / 2
	end
	return {
		update = function(t: number, dt: number)
			for _, m in movers do
				m.x += m.vx * dt * ctx.speed
				m.y += m.vy * dt * ctx.speed
				if m.x < 4 or m.x > ctx.w - 16 then
					m.vx = -m.vx
				end
				if m.y < 12 or m.y > ctx.h - 36 then
					m.vy = -m.vy
				end
				m.x, m.y = math.clamp(m.x, 4, ctx.w - 16), math.clamp(m.y, 12, ctx.h - 36)
				-- they march: a pixel's hop every other step
				local hop = if math.floor(t * 8 + m.x * 0.1) % 2 == 0 then 1 else 0
				m.f.Position = UDim2.fromOffset(snap(m.x), snap(m.y) - hop)
			end
			for i, bo in bobs do
				local up = if math.floor(t * 3 + i * 0.5) % 4 == 0 then 1 else 0
				bo.f.Position = UDim2.fromOffset(bo.x, bo.y - up)
			end
		end,
		key = function(k: string)
			local i = tonumber(k)
			if i and i >= 1 and i <= n then
				choose(i)
			end
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
	if ctx.variant == "simon" then
		-- four coloured pads flash a tune; play it back
		local len = 2 + math.floor(ctx.diff / 2)
		local seq: { number } = {}
		for i = 1, len do
			seq[i] = ctx.rng:int(1, 4)
		end
		local colors = { "fun", "ideas", "graphics", "sound" }
		local pads: { TextButton } = {}
		local pw = 40
		local total = 4 * (pw + 6) - 6
		local py = math.floor(ctx.h / 2) - 14
		for i = 1, 4 do
			local b = pad(ctx, tostring(i), tostring(i), (ctx.w - total) / 2 + (i - 1) * (pw + 6), py, pw, 30, "plate_light")
			UIKit.setButtonColor(b, UIKit.color(colors[i]):Lerp(INK, 0.5))
			pads[i] = b
		end
		local label = say(ctx, "Watch...")
		local step = 0.5 / ctx.speed
		local showing = true
		local at = 1
		local done = false
		local lit = 0
		local noteName = pick(ctx, "note")
		local function light(i: number, on: boolean)
			UIKit.setButtonColor(pads[i], if on then UIKit.color(colors[i]):Lerp(WHITE, 0.15) else UIKit.color(colors[i]):Lerp(INK, 0.5))
			if on then
				local x = pads[i].Position.X.Offset + pw / 2
				local note = img(ctx.area, noteName, x - 5, py - 6, 13)
				ctx.float(note, (ctx.rng:next() - 0.5) * 12, -30, 0.6)
				ctx.burst(x, py, { colors[i], "white" }, 4)
			end
		end
		local function press(i: number)
			if showing or done then
				return
			end
			light(i, true)
			task.delay(0.15, function()
				if pads[i].Parent then
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
		return {
			clock = 1.6,
			update = function(t: number, _dt: number)
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
			key = function(k: string)
				local i = tonumber(k) or table.find(DIRS, k)
				if i then
					press(i)
				end
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
	local tx0, ty = math.floor((ctx.w - total) / 2), 14
	type Tile = { p: Frame, a: GuiObject, x: number }
	local tiles: { Tile } = {}
	for i = 1, len do
		local x = tx0 + (i - 1) * (tw + 3)
		local p = UIKit.plate(ctx.area, UDim2.fromOffset(tw, tw), UDim2.fromOffset(x, ty), UIKit.color("plate_light"), 0, 2)
		p.ZIndex = 8
		local a = img(p, "arrow_" .. seq[i] .. suffix, math.floor((tw - aw) / 2), math.floor((tw - aw) / 2), 9)
		tiles[i] = { p = p, a = a, x = x }
	end
	-- the theme below the tiles: the robot on its board walks each arrow to the star; the hat sparkles
	local bx0, by0 = 0, 0
	local cell = 13
	local bcols, brows = 9, 3
	local robot: PixelSprites.Anim? = nil
	local rpos = Vector2.zero
	local hat: PixelSprites.Anim? = nil
	local hatX, hatY = 0, 0
	if program then
		by0 = ty + tw + 6
		brows = math.clamp(math.floor((ctx.h - 20 - by0) / cell), 2, 4)
		bx0 = math.floor((ctx.w - bcols * cell) / 2)
		-- the board: an ink-edged plate, a dot at each cell's corner
		box(ctx.area, bcols * cell + 3, brows * cell + 3, bx0 - 1, by0 - 1, "ink", 7)
		UIKit.rect(ctx.area, UDim2.fromOffset(bcols * cell + 1, brows * cell + 1), UDim2.fromOffset(bx0, by0), UIKit.hex(0x2E6A48), 7).Name = "Board"
		UIKit.rect(ctx.area, UDim2.fromOffset(bcols * cell + 1, 1), UDim2.fromOffset(bx0, by0), UIKit.hex(0x4E9A6A), 7)
		for c = 0, bcols do
			for r = 0, brows do
				local d = box(ctx.area, 1, 1, bx0 + c * cell, by0 + r * cell, "white", 7)
				d.BackgroundTransparency = 0.35
			end
		end
		rpos = Vector2.new(math.floor(bcols / 2), math.floor(brows / 2))
		local goal = rpos
		for _, d in seq do
			local nx = goal + STEP[d]
			goal = Vector2.new(math.clamp(nx.X, 0, bcols - 1), math.clamp(nx.Y, 0, brows - 1))
		end
		img(ctx.area, "star", bx0 + goal.X * cell + 4, by0 + goal.Y * cell + 4, 8)
		robot = anim(ctx.area, { "mini_robots" }, bx0 + rpos.X * cell + 1, by0 + rpos.Y * cell + 1, 9)
	else
		hatX, hatY = math.floor(ctx.w / 2) - 8, ty + tw + 14
		hat = anim(ctx.area, { "icon_fantasy" }, hatX, hatY, 9)
	end
	local hideAt = if program and ctx.diff >= 4 then 1.2 / ctx.speed else math.huge
	local hidden = false
	local at = 1
	local done = false
	say(ctx, if program then "Program the robot!" else "Cast the spell!")
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
			if robot then
				local nx = rpos + STEP[k]
				rpos = Vector2.new(math.clamp(nx.X, 0, bcols - 1), math.clamp(nx.Y, 0, brows - 1))
				UIKit.tween((robot :: PixelSprites.Anim).f, 0.08, { Position = UDim2.fromOffset(bx0 + rpos.X * cell + 1, by0 + rpos.Y * cell + 1) })
			end
			if hat then
				local star = img(ctx.area, "star", hatX + 6, hatY - 2, 12)
				ctx.float(star, (ctx.rng:next() - 0.5) * 40, -40, 0.5, 60)
			end
			at += 1
			highlight()
			if at > len then
				done = true
				if robot then
					ctx.burst(bx0 + rpos.X * cell + 6, by0 + rpos.Y * cell + 6, { "yellow", "white", "good" }, 14)
				end
				if hat then
					(hat :: PixelSprites.Anim).flash(0.15)
					ctx.burst(hatX + 8, hatY + 4, { "purple", "yellow", "white", "pink" }, 20)
				end
				ctx.win()
			end
		else
			done = true
			UIKit.setPlate(tl.p, UIKit.color("bad"))
			tl.a.Visible = true
			if robot then
				(robot :: PixelSprites.Anim).flash(0.3)
			end
			if hat then
				(hat :: PixelSprites.Anim).flash(0.3)
			end
			ctx.shake()
			ctx.lose()
		end
	end
	return {
		update = function(t: number, _dt: number)
			if not hidden and t >= hideAt then
				hidden = true
				for i, tl in tiles do
					if i >= at then
						tl.a.Visible = false
					end
				end
			end
			if hat and not done then
				(hat :: PixelSprites.Anim).moveTo(hatX, hatY - (if math.floor(t * 3) % 2 == 0 then 0 else 1))
			end
		end,
		key = typeKey,
		auto = function()
			if seq[at] then
				typeKey(seq[at])
			end
		end,
	}
end

------------------------------------------------------------------ 7. catch (Pirates "Loot!", Ocean "Catch!")
function Games.catch(ctx: Ctx): Micro
	local fish = ctx.variant == "fish"
	local n = if ctx.diff >= 5 then 5 else 4
	local L = lanes(ctx, n, { pick(ctx, "basket") })
	local goodNames = if fish then framesOf(ctx, "fish", 2) else framesOf(ctx, "coin", 3)
	local badNames = if fish then framesOf(ctx, "jelly", 2) else framesOf(ctx, "bomb", 2)
	local gw, gh = PixelSprites.size(goodNames[1])
	local bw, bh = PixelSprites.size(badNames[1])
	local need = 3 + math.floor(ctx.diff / 2)
	local got = 0
	local items: { Faller } = {}
	local nextAt = 0.3
	local fall = (42 + 8 * ctx.diff) * ctx.speed
	local every = math.max(0.3, 0.7 - 0.05 * ctx.diff) / ctx.speed
	local badShare = math.min(0.5, 0.2 + 0.04 * ctx.diff)
	local done = false
	local verb = if fish then "Catch fish, not jellies:" else "Grab coins, not bombs:"
	local label = say(ctx, string.format("%s 0/%d", verb, need))
	return {
		update = function(t: number, dt: number)
			if done then
				return
			end
			if t >= nextAt then
				nextAt = t + every * (0.7 + 0.6 * ctx.rng:next())
				local l = ctx.rng:int(1, n)
				local good = not ctx.rng:chance(badShare)
				local w, h = if good then gw else bw, if good then gh else bh
				local a = anim(ctx.area, if good then goodNames else badNames, L.xOf(l, w), -h, 9)
				table.insert(items, { a = a, lane = l, y = -h, w = w, h = h, good = good, gone = false })
			end
			local frame = math.floor(t * 8) + 1
			for _, it in items do
				if not it.gone then
					it.y += fall * dt
					it.a.moveTo(L.xOf(it.lane, it.w), it.y)
					it.a.set(frame)
					if it.lane == L.lane() and it.y + it.h > L.my + 2 and it.y < L.my + 4 then
						it.gone = true
						it.a.f:Destroy()
						local cx = L.xOf(it.lane, 0)
						if it.good then
							got += 1
							Audio.play("coin")
							L.bump()
							ctx.burst(cx, L.my, if fish then { "orange", "white", "blue" } else { "yellow", "white", "gold" }, 8)
							ctx.pop(cx, L.my - 10, "+1", UIKit.color("accent"))
							UIKit.setText(label, string.format("%s %d/%d", verb, got, need))
							if got >= need then
								done = true
								ctx.win()
								return
							end
						else
							done = true
							L.me.flash(0.3)
							ctx.burst(cx, L.my, if fish then { "pink", "white", "purple" } else { "orange", "yellow", "bad", "white" }, 18)
							if not fish then
								ctx.flash("white")
							end
							ctx.shake()
							ctx.lose()
							return
						end
					elseif it.y > ctx.h - 18 then
						it.gone = true
						it.a.f:Destroy()
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
		auto = function()
			-- a bad thing about to land in a lane
			local function badNear(l: number): boolean
				for _, it in items do
					if not it.gone and not it.good and it.lane == l and it.y > L.my - it.h - 30 and it.y < L.my + 4 then
						return true
					end
				end
				return false
			end
			local here = L.lane()
			-- the lowest good thing in a lane that is safe to wait in
			local best: Faller? = nil
			for _, it in items do
				if not it.gone and it.good and it.y < L.my and not badNear(it.lane) and (best == nil or it.y > (best :: Faller).y) then
					best = it
				end
			end
			local target = if best then (best :: Faller).lane else here
			if badNear(here) and target == here then
				for _, d in { -1, 1, -2, 2 } do
					local l = here + d
					if l >= 1 and l <= n and not badNear(l) then
						target = l
						break
					end
				end
			end
			if target ~= here then
				local step = if target > here then 1 else -1
				if not badNear(here + step) or badNear(here) then
					L.move(step)
				end
			end
		end,
	}
end

------------------------------------------------------------------ 8. jump (Adventure "Leap!", Dinosaurs "Jump!")
function Games.jump(ctx: Ctx): Micro
	local dino = ctx.variant == "dino"
	local ground = ctx.h - 22
	local names = framesOf(ctx, if dino then "dino" else "hero", 2)
	local hw, hh = PixelSprites.size(names[1])
	local px0 = 30
	local me = anim(ctx.area, names, px0, ground - hh, 10)
	local obName = pick(ctx, if dino then "cactus" else "rock")
	local ow, oh = PixelSprites.size(obName)
	type Ob = { g: GuiObject, x: number, gone: boolean }
	local obs: { Ob } = {}
	local speed = (70 + 11 * ctx.diff) * ctx.speed
	-- specks on the ground run past: the world scrolls
	type Speck = { f: Frame, x: number }
	local specks: { Speck } = {}
	for i = 1, 10 do
		local f = box(ctx.area, if i % 3 == 0 then 2 else 1, 1, 0, ground + 3 + (i * 5) % 14, if dino then "wood" else "wood_dark", 6)
		f.Name = "Speck"
		table.insert(specks, { f = f, x = (i * 37) % ctx.w })
	end
	local nextAt = 0.6
	local jumpT = -1
	local JUMP = 0.62 / ctx.speed
	local H = if ctx.tiny then 28 else 34
	local y = 0
	local dead = false
	local dust = if dino then { "yellow", "wood" } else { "white", "leaf" }
	pad(ctx, "Jump!", "go", ctx.w - 64, ctx.h - 16, 60, 16, "accent")
	say(ctx, if dino then "Jump the cacti!" else "Leap over the rocks!")
	local now = 0
	local function jump()
		if jumpT < 0 and not dead then
			jumpT = now
			Audio.play("pop", { pitch = 1.3 })
			ctx.burst(px0 + hw / 2, ground - 1, dust, 4)
		end
	end
	return {
		survive = true,
		update = function(t: number, dt: number)
			now = t
			if dead then
				return
			end
			for _, s in specks do
				s.x -= speed * dt
				if s.x < -2 then
					s.x += ctx.w + 4
				end
				s.f.Position = UDim2.fromOffset(snap(s.x), s.f.Position.Y.Offset)
			end
			if jumpT >= 0 then
				local k = (t - jumpT) / JUMP
				if k >= 1 then
					jumpT = -1
					y = 0
					ctx.burst(px0 + hw / 2, ground - 1, dust, 5)
				else
					y = math.floor(4 * H * k * (1 - k))
				end
			end
			me.set(if y > 0 then 1 else math.floor(t * 10) + 1)
			me.moveTo(px0, ground - hh - y)
			if t >= nextAt then
				nextAt = t + math.max(0.55, (1.25 - 0.06 * ctx.diff)) / ctx.speed * (0.8 + 0.5 * ctx.rng:next())
				table.insert(obs, { g = img(ctx.area, obName, ctx.w, ground - oh, 9), x = ctx.w, gone = false })
			end
			for _, o in obs do
				if not o.gone then
					o.x -= speed * dt
					o.g.Position = UDim2.fromOffset(snap(o.x), ground - oh)
					if o.x < px0 + hw - 3 and o.x + ow - 3 > px0 and y < oh - 3 then
						dead = true
						me.flash(0.3)
						ctx.burst(px0 + hw, ground - hh / 2, { "white", "bad", "accent" }, 12)
						ctx.shake()
						ctx.lose()
						return
					end
					if o.x < -ow - 2 then
						o.gone = true
						o.g:Destroy()
					end
				end
			end
		end,
		key = function(k: string)
			if k == "go" or k == "up" then
				jump()
			end
		end,
		auto = function()
			for _, o in obs do
				if not o.gone and o.x > px0 and o.x - px0 < hw + 4 + speed * 0.12 then
					jump()
					return
				end
			end
		end,
	}
end

------------------------------------------------------------------ 9. rhythm (Rhythm "Tap the beat!")
function Games.rhythm(ctx: Ctx): Micro
	local nLanes = if ctx.diff >= 5 then 3 else 2
	local count = 6 + ctx.diff
	local beat = math.max(0.3, 0.55 - 0.025 * ctx.diff) / ctx.speed
	local travel = 1.1 / ctx.speed
	local win = math.max(0.1, 0.2 - 0.01 * ctx.diff)
	local allowed = math.max(0, 2 - math.floor(ctx.diff / 3))
	type Note = { t: number, lane: number, g: GuiObject?, judged: boolean }
	local notes: { Note } = {}
	local tt = 0.9
	for _ = 1, count do
		table.insert(notes, { t = tt, lane = ctx.rng:int(1, nLanes), judged = false })
		tt += beat * (if ctx.rng:chance(0.25) then 0.5 else 1)
	end
	local lastT = notes[#notes].t
	local lw = 30
	local x0 = math.floor((ctx.w - nLanes * (lw + 4)) / 2)
	local hitY = ctx.h - 30
	local keysFor = { { "left", "1" }, { "down", "2", "go" }, { "right", "3" } }
	if nLanes == 2 then
		keysFor = { { "left", "1" }, { "right", "2", "go" } }
	end
	local laneColors = { "sound", "fun", "ideas" }
	local noteName = pick(ctx, "note")
	local nw, nh = PixelSprites.size(noteName)
	local receptors: { Frame } = {}
	for l = 1, nLanes do
		local lx = x0 + (l - 1) * (lw + 4)
		local strip = box(ctx.area, lw, hitY - 10, lx, 12, "ink", 7)
		strip.BackgroundTransparency = 0.25
		box(ctx.area, 1, hitY - 10, lx, 12, "white", 7).BackgroundTransparency = 0.8
		box(ctx.area, 1, hitY - 10, lx + lw - 1, 12, "white", 7).BackgroundTransparency = 0.8
		receptors[l] = block(ctx.area, lw - 4, 7, lx + 2, hitY - 3, UIKit.color(laneColors[l]):Lerp(INK, 0.45), 8)
		pad(ctx, tostring(l), tostring(l), lx, ctx.h - 16, lw, 16, laneColors[l])
	end
	local misses = 0
	local now = 0
	local done = false
	local label = say(ctx, string.format("Tap on the line! Misses %d/%d", 0, allowed))
	local function glow(l: number, color: Color3)
		local fill = receptors[l]:FindFirstChild("Fill")
		if fill and fill:IsA("Frame") then
			fill.BackgroundColor3 = color
			task.delay(0.1, function()
				if fill.Parent then
					fill.BackgroundColor3 = UIKit.color(laneColors[l]):Lerp(INK, 0.45)
				end
			end)
		end
	end
	local function laneX(l: number): number
		return x0 + (l - 1) * (lw + 4)
	end
	local function miss(l: number?)
		misses += 1
		UIKit.setText(label, string.format("Tap on the line! Misses %d/%d", misses, allowed))
		if l then
			glow(l, UIKit.color("bad"))
			ctx.pop(laneX(l) + lw / 2, hitY - 14, "Miss", UIKit.color("bad"))
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
		for _, n in notes do
			if not n.judged and n.lane == l and math.abs(n.t - now) <= win and (best == nil or math.abs(n.t - now) < math.abs((best :: Note).t - now)) then
				best = n
			end
		end
		if best then
			local b = best :: Note
			b.judged = true
			if b.g then
				(b.g :: GuiObject):Destroy()
			end
			Audio.play("tick", { pitch = 0.9 + l * 0.15 })
			local perfect = math.abs(b.t - now) < win / 2
			glow(l, UIKit.color(laneColors[l]):Lerp(WHITE, 0.3))
			ctx.burst(laneX(l) + lw / 2, hitY, { laneColors[l], "white" }, if perfect then 10 else 6)
			ctx.pop(laneX(l) + lw / 2, hitY - 14, if perfect then "Perfect!" else "Good", UIKit.color(if perfect then "yellow" else "accent"))
		else
			miss(l)
		end
	end
	return {
		clock = 99, -- the song decides: it ends after its last note
		update = function(t: number, _dt: number)
			now = t
			if done then
				return
			end
			local open = false
			for _, n in notes do
				if not n.judged then
					open = true
					local dt = n.t - t
					if dt < -win then
						n.judged = true
						if n.g then
							(n.g :: GuiObject):Destroy()
						end
						miss(n.lane)
					elseif dt <= travel then
						local yy = hitY - math.floor(dt / travel * (hitY - 14)) - math.floor(nh / 2)
						if n.g == nil then
							n.g = img(ctx.area, noteName, 0, 0, 10)
						end
						(n.g :: GuiObject).Position = UDim2.fromOffset(laneX(n.lane) + math.floor((lw - nw) / 2), yy)
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
		auto = function()
			for _, n in notes do
				if not n.judged and math.abs(n.t - now) <= win * 0.4 then
					hit(n.lane)
					return
				end
			end
		end,
	}
end

------------------------------------------------------------------ 10. slice (Ninjas "Slice!")
function Games.slice(ctx: Ctx): Micro
	local need = 4 + math.floor(ctx.diff / 2)
	local got = 0
	local fruitName = pick(ctx, "fruit")
	local bombNames = framesOf(ctx, "bomb", 2)
	local fw, fh = PixelSprites.size(fruitName)
	local bw, bh = PixelSprites.size(bombNames[1])
	type Fly = { b: TextButton, a: PixelSprites.Anim, x: number, y: number, vx: number, vy: number, w: number, h: number, bomb: boolean, gone: boolean }
	local flies: { Fly } = {}
	local nextAt = 0.2
	local every = math.max(0.3, 0.75 - 0.05 * ctx.diff) / ctx.speed
	local g = 150 * ctx.speed * ctx.speed
	local done = false
	local k = 0
	local label = say(ctx, string.format("Slice the fruit, not the bombs! 0/%d", need))
	-- a slash: a 1 px diagonal (a clean 1:1 line, no jaggies) that is gone in a blink
	local function slash(x: number, y: number, len: number)
		local f = Instance.new("Frame")
		f.Name = "Slash"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromOffset(len, len)
		f.Position = UDim2.fromOffset(snap(x), snap(y))
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
		local cx, cy = f.x + 3 + f.w / 2, f.y + 3 + f.h / 2
		slash(cx - f.w / 2 - 2, cy - f.w / 2 - 2, f.w + 4)
		if f.bomb then
			done = true
			ctx.flash("white")
			ctx.burst(cx, cy, { "orange", "yellow", "bad", "white" }, 20)
			ctx.shake()
			ctx.pop(cx, f.y, "Boom!", UIKit.color("bad"))
			ctx.lose()
			return
		end
		got += 1
		Audio.play("squish", { pitch = 1.2 })
		if not ctx.tiny then
			-- two halves fly apart and fall
			local hw = PixelSprites.size("fruit_cut")
			local left = img(ctx.area, "fruit_cut", cx - hw, cy - 2, 12)
			local right = img(ctx.area, "fruit_cut", cx + 1, cy - 2, 12)
			ctx.float(left, f.vx - 30, -20, 0.6, 300)
			ctx.float(right, f.vx + 30, -26, 0.6, 300)
		end
		ctx.burst(cx, cy, { "berry_red", "pink", "green" }, 10)
		ctx.pop(cx, f.y, "Slice!", UIKit.color("good"))
		UIKit.setText(label, string.format("Slice the fruit, not the bombs! %d/%d", got, need))
		if got >= need then
			done = true
			ctx.win()
		end
	end
	return {
		update = function(t: number, dt: number)
			if done then
				return
			end
			if t >= nextAt then
				nextAt = t + every * (0.7 + 0.6 * ctx.rng:next())
				k += 1
				local bomb = ctx.diff >= 3 and ctx.rng:chance(0.25)
				local w, h = if bomb then bw else fw, if bomb then bh else fh
				local b = hitbox(ctx, (if bomb then "Bomb_" else "Fruit_") .. k, w + 6, h + 6, 0, ctx.h, 9)
				local a = anim(b, if bomb then bombNames else { fruitName }, 3, 3, 10)
				local fl: Fly = { b = b, a = a, x = ctx.rng:int(20, ctx.w - 30), y = ctx.h, vx = (ctx.rng:next() - 0.5) * 60 * ctx.speed, vy = -(130 + ctx.rng:next() * 40) * ctx.speed, w = w, h = h, bomb = bomb, gone = false }
				b.Activated:Connect(function()
					cut(fl)
				end)
				table.insert(flies, fl)
			end
			local frame = math.floor(t * 10) + 1
			for _, f in flies do
				if not f.gone then
					f.vy += g * dt
					f.x += f.vx * dt
					f.y += f.vy * dt
					f.a.set(frame)
					f.b.Position = UDim2.fromOffset(snap(f.x), snap(f.y))
					if f.y > ctx.h + 4 and f.vy > 0 then
						f.gone = true
						f.b:Destroy()
					end
				end
			end
		end,
		key = function(_k: string) end,
		auto = function()
			for _, f in flies do
				if not f.gone and not f.bomb and f.y < ctx.h - 20 then
					cut(f)
					return
				end
			end
		end,
	}
end

------------------------------------------------------------------ 11. hide (Horror "Sneak!")
function Games.hide(ctx: Ctx): Micro
	local steps = 5 + ctx.diff
	local at = 0
	local x0, x1 = 16, ctx.w - 60
	local floorY = ctx.h - 24
	local dw, dh = PixelSprites.size("door")
	img(ctx.area, "door", x1 + 14, floorY - dh, 8)
	local kidName = pick(ctx, "kid")
	local kw, kh = PixelSprites.size(kidName)
	local me = anim(ctx.area, { kidName }, x0, floorY - kh, 10)
	local gw = PixelSprites.size("ghost")
	local gx = math.floor(ctx.w / 2 - gw / 2)
	local ghost = anim(ctx.area, { "ghost" }, gx, 13, 9)
	local glare = anim(ctx.area, { "ghost_glare" }, gx, 13, 9)
	glare.f.Visible = false
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
	local function kidX(i: number): number
		return math.floor(x0 + (x1 - x0) * i / steps)
	end
	local function step()
		if done then
			return
		end
		if state == "watch" then
			done = true
			me.flash(0.3)
			glare.flash(0.2)
			ctx.shake()
			ctx.pop(kidX(at) + kw / 2, floorY - kh - 12, "Seen!", UIKit.color("bad"))
			ctx.lose()
			return
		end
		at += 1
		Audio.play("key", { pitch = 0.8 })
		-- a little hop to the next board
		me.moveTo(kidX(at - 1), floorY - kh - 2)
		UIKit.tween(me.f, 0.08, { Position = UDim2.fromOffset(kidX(at), floorY - kh) })
		ctx.burst(kidX(at - 1) + 2, floorY - 1, { "wood_dark", "text_dim" }, 3)
		if at >= steps then
			done = true
			ctx.burst(x1 + 14 + dw / 2, floorY - dh / 2, { "yellow", "white", "good" }, 14)
			ctx.win()
		end
	end
	pad(ctx, "Step", "go", ctx.w / 2 - 30, ctx.h - 16, 60, 16, "accent")
	return {
		clock = 1.5,
		update = function(t: number, _dt: number)
			now = t
			if done then
				return
			end
			if t >= untilT then
				if state == "away" then
					state = "warn"
					untilT = t + warnT
					ctx.pop(gx + gw / 2, 10, "!", UIKit.color("accent"))
				elseif state == "warn" then
					state = "watch"
					untilT = t + (0.6 + 0.6 * ctx.rng:next()) / ctx.speed
				else
					state = "away"
					untilT = t + math.max(0.4, (1.2 - 0.07 * ctx.diff + ctx.rng:next() * 0.8)) / ctx.speed
				end
				UIKit.setText(eyes, if state == "watch" then "It's watching! Freeze!" elseif state == "warn" then "It's turning..." else "Sneak while it looks away!")
				UIKit.setTextColor(eyes, if state == "watch" then UIKit.color("bad") elseif state == "warn" then UIKit.color("accent") else UIKit.color("text"))
			end
			local jig = if state == "warn" then (if math.floor(t * 30) % 2 == 0 then 2 else -2) else 0
			local bob = if math.floor(t * 3) % 2 == 0 then 0 else 1
			ghost.moveTo(gx + jig, 13 + bob)
			glare.moveTo(gx, 13)
			ghost.f.Visible = state ~= "watch"
			glare.f.Visible = state == "watch"
			red.BackgroundTransparency = if state == "watch" then 0.88 else 1
		end,
		key = function(k: string)
			if k == "go" or k == "right" then
				step()
			end
		end,
		auto = function()
			if state == "away" and untilT - now > 0.12 then
				step()
			end
		end,
	}
end

------------------------------------------------------------------ 12. stack (Simulation "Build!")
-- Floors swing on a crane: drop each on the one below; what hangs over falls off.
local FLOOR_COLORS = { 0x70A9EA, 0x6FD3F2, 0xA77DD7, 0xFFA553, 0x6CC06A, 0xFFA7CA, 0xFFCB30 }
function Games.stack(ctx: Ctx): Micro
	local need = 3 + math.floor(ctx.diff / 2)
	local bh = if ctx.tiny then 6 else 8
	local baseY = ctx.h - 22
	local w = if ctx.tiny then 40 else 70
	local topX = math.floor((ctx.w - w) / 2)
	local function floor(x: number, y: number, fw: number, level: number): Frame
		local f = block(ctx.area, fw, bh, x, y, UIKit.hex(if level == 0 then 0xAEB8C5 else FLOOR_COLORS[(level - 1) % #FLOOR_COLORS + 1]), 9)
		f.Name = "Floor"
		if level > 0 then
			-- its windows, some lit
			local wy = if ctx.tiny then 2 else 3
			for wx = 3, fw - 4, 4 do
				local lit = ((wx * 7 + level * 13) % 5) < 3
				UIKit.rect(f, UDim2.fromOffset(2, 2), UDim2.fromOffset(wx, wy), UIKit.hex(if lit then 0xFFF0A0 else 0x24346E), 9)
			end
		end
		return f
	end
	floor(topX, baseY - bh, w, 0)
	local level = 1
	local moving = floor(0, baseY - bh * 2, w, level)
	local rope = box(ctx.area, 1, 1, 0, 11, "ink", 8)
	rope.Name = "Rope"
	local hook = box(ctx.area, 3, 2, 0, 0, "steel_dark", 8)
	hook.Name = "Hook"
	local mx, dir = 0, 1
	local speed = (60 + 12 * ctx.diff) * ctx.speed
	local done = false
	local label = say(ctx, string.format("Drop the floors! 0/%d", need))
	local function hang()
		local y = baseY - bh * (level + 1)
		local cx = math.floor(mx + w / 2)
		rope.Position = UDim2.fromOffset(cx, 11)
		rope.Size = UDim2.fromOffset(1, math.max(0, y - 13))
		hook.Position = UDim2.fromOffset(cx - 1, y - 2)
	end
	local function drop()
		if done then
			return
		end
		local x = math.floor(mx)
		local y = baseY - bh * (level + 1)
		if math.abs(x - topX) <= 1 then
			x = topX -- near enough is perfect
		end
		local left = math.max(x, topX)
		local right = math.min(x + w, topX + w)
		local overlap = right - left
		if overlap <= 0 then
			done = true
			ctx.float(moving, (if x < topX then -30 else 30), 0, 0.7, 300)
			ctx.shake()
			ctx.lose()
			return
		end
		Audio.play("pop", { pitch = 0.8 + level * 0.1 })
		moving:Destroy()
		-- what hangs over falls off
		if overlap < w then
			local cutX = if x < topX then x else right
			local chunk = floor(cutX, y, w - overlap, level)
			ctx.float(chunk, if x < topX then -24 else 24, -10, 0.8, 320)
		end
		floor(left, y, overlap, level)
		ctx.burst(left, y + bh, { "white", "steel" }, 3)
		ctx.burst(left + overlap, y + bh, { "white", "steel" }, 3)
		if overlap == w then
			ctx.pop(left + overlap / 2, y - 10, "Perfect!", UIKit.color("yellow"))
		end
		topX, w = left, overlap
		UIKit.setText(label, string.format("Drop the floors! %d/%d", level, need))
		if level >= need then
			done = true
			rope.Visible = false
			hook.Visible = false
			ctx.burst(left + overlap / 2, y, { "yellow", "white", "good" }, 16)
			ctx.win()
			return
		end
		level += 1
		mx, dir = if ctx.rng:chance(0.5) then 0 else ctx.w - w, if ctx.rng:chance(0.5) then 1 else -1
		moving = floor(mx, baseY - bh * (level + 1), w, level)
		hang()
	end
	pad(ctx, "Drop!", "go", ctx.w - 64, ctx.h - 16, 60, 16, "accent")
	hang()
	return {
		clock = 1.5,
		update = function(_t: number, dt: number)
			if done then
				return
			end
			mx += dir * speed * dt
			if mx >= ctx.w - w then
				mx, dir = ctx.w - w, -1
			elseif mx <= 0 then
				mx, dir = 0, 1
			end
			moving.Position = UDim2.fromOffset(math.floor(mx), baseY - bh * (level + 1))
			hang()
		end,
		key = function(k: string)
			if k == "go" or k == "down" then
				drop()
			end
		end,
		auto = function()
			if math.abs(mx - topX) <= math.max(3, speed * 0.06) then
				drop()
			end
		end,
	}
end

return Games
