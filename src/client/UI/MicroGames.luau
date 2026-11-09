--!strict
-- The microgames (GAME_DESIGN 5; docs/ARCHITECTURE.md 10.8): twelve engines, each played by one or more ideas in
-- their own theme (Data/Ideas micro + variant), WarioWare style: a one-word order, a few seconds, win or lose. An
-- engine gets the play area and a context (the difficulty 1..8 from the idea's rarity, the Turbo speed, the Tiny
-- scale, an Rng seeded by the server) and calls ctx.win() or ctx.lose(); one that is `survive` wins when the clock
-- runs out first. MicroUI runs the clock and the modifiers' screen effects (shake, glitch, dark). Every button a sim
-- can press has a name (Pad_<key>, Hole_<i>, Opt_<i>, Fruit_<i>); `auto` makes one right move (the sims' player).
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
	px: number, -- sprite scale: 2, or 1 when Tiny
	variant: string,
	pop: (x: number, y: number, text: string, color: Color3) -> (),
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
	auto: () -> (),
}

local Games = {}

------------------------------------------------------------------ helpers
local function sprite(parent: Instance, s: PixelSprites.Sprite, x: number, y: number, scale: number, z: number?): Frame
	return PixelSprites.sprite(parent, s, UDim2.fromOffset(math.floor(x), math.floor(y)), scale, z or 9)
end

local function box(parent: Instance, w: number, h: number, x: number, y: number, color: string, z: number?): Frame
	return UIKit.rect(parent, UDim2.fromOffset(w, h), UDim2.fromOffset(math.floor(x), math.floor(y)), UIKit.color(color), z or 8)
end

-- A touch pad along the area's bottom (or anywhere): it presses `key`.
local function pad(ctx: Ctx, text: string, key: string, x: number, y: number, w: number, h: number, color: string?): TextButton
	local b = UIKit.button(ctx.area, text, UDim2.fromOffset(w, h), UDim2.fromOffset(math.floor(x), math.floor(y)), function()
		ctx.press(key)
	end, { name = "Pad_" .. key, color = UIKit.color(color or "plate_light") })
	b.ZIndex = 10
	return b
end

local function arrowsPads(ctx: Ctx, keys: { string })
	local pw, ph = 26, 16
	local total = #keys * (pw + 3) - 3
	for i, k in keys do
		local b = pad(ctx, "", k, (ctx.w - total) / 2 + (i - 1) * (pw + 3), ctx.h - ph, pw, ph)
		PixelSprites.draw(b, PixelSprites.ARROWS[k], { ["#"] = "text" }, UDim2.fromOffset(math.floor((pw - 7) / 2), math.floor((ph - 7) / 2)), 1, 11)
	end
end

-- A one-line hint at the top of the area.
local function say(ctx: Ctx, text: string, color: string?): TextLabel
	return UIKit.text(ctx.area, text, UDim2.fromOffset(ctx.w, 10), UDim2.fromOffset(0, 0), { x = "center", color = UIKit.color(color or "text"), z = 12, name = "Say" })
end

-- small things the engines draw (8x8 at px scale)
local BLOCK = PixelSprites.S({ "########", "#rrrrrr#", "#rwrrrr#", "#rrrrrr#", "#rrrrrr#", "#rrrrrr#", "#rrrrrr#", "########" }, { ["#"] = "ink", r = "berry_red", w = "pink" })
local CONE = PixelSprites.S({ "...##...", "..#oo#..", "..#ww#..", ".#oooo#.", ".#wwww#.", "#oooooo#", "########", "........" }, { ["#"] = "ink", o = "orange", w = "white" })
local HERO = PixelSprites.S({ "..####..", "..#ss#..", "..####..", ".#bbbb#.", "#.#bb#.#", "..#bb#..", "..#..#..", ".##..##." }, { ["#"] = "ink", s = "skin2", b = "blue" })
local COIN = PixelSprites.S({ "..####..", ".#yyyy#.", "#yywyyy#", "#yyyyyy#", "#yyyyyy#", "#yyyyyy#", ".#yyyy#.", "..####.." }, { ["#"] = "ink", y = "gold", w = "white" })
local BOMB = PixelSprites.S({ "....#.y.", "...#....", "..####..", ".#kkkk#.", "#kwkkkk#", "#kkkkkk#", ".#kkkk#.", "..####.." }, { ["#"] = "ink", k = "black", w = "white", y = "yellow" })
local FISH = PixelSprites.S({ "........", "..####.#", ".#bbbb##", "#bwbbbb#", "#bbbbbb#", ".#bbbb##", "..####.#", "........" }, { ["#"] = "ink", b = "orange", w = "white" })
local JELLY = PixelSprites.S({ "..####..", ".#pppp#.", "#pwpppp#", "#pppppp#", "########", ".#.#.#..", "#.#.#.#.", ".#.#.#.." }, { ["#"] = "ink", p = "pink", w = "white" })
local BASKET = PixelSprites.S({ "#......#", "#......#", "#wwwwww#", "#w#ww#w#", "#wwwwww#", ".#w##w#.", ".######.", "........" }, { ["#"] = "ink", w = "wood" })
local ALIEN = PixelSprites.S({ ".#....#.", "..#..#..", ".######.", "#gggggg#", "#g#gg#g#", "#gggggg#", ".#g##g#.", "#.#..#.#" }, { ["#"] = "ink", g = "green" })
local SPROUT = PixelSprites.S({ "........", "..#..#..", ".#w##w#.", "..#ww#..", "...##...", "..####..", ".#pppp#.", ".######." }, { ["#"] = "ink", w = "wood", p = "pot" })
local FLOWER = PixelSprites.S({ "..#..#..", ".#y##y#.", "#yyrryy#", ".#y##y#.", "...##...", "..####..", ".#pppp#.", ".######." }, { ["#"] = "ink", y = "yellow", r = "berry_red", p = "pot" })
local KID = PixelSprites.S({ "..####..", ".#hhhh#.", ".#ssss#.", ".#s#s##.", "..####..", ".#bbbb#.", "#.#bb#.#", "..#..#.." }, { ["#"] = "ink", h = "hair_brown", s = "skin2", b = "blue" })
local FRUIT = PixelSprites.S({ "...#l#..", "..####..", ".#rrrr#.", "#rwrrrr#", "#rrrrrr#", "#rrrrrr#", ".#rrrr#.", "..####.." }, { ["#"] = "ink", r = "green", w = "white", l = "wood" })
local ROCK = PixelSprites.S({ "........", "........", "..####..", ".#ssss#.", "#sswsss#", "#ssssss#", "#ssssss#", "########" }, { ["#"] = "ink", s = "steel", w = "white" })
local CACTUS = PixelSprites.S({ "...##...", "...#g#..", "#.#g#.#.", "#g#g##g#", "#ggggg#.", "..#g#...", "..#g#...", ".#####.." }, { ["#"] = "ink", g = "leaf" })
local DOOR = PixelSprites.S({ "########", "#wwwwww#", "#wwwwww#", "#wwwwyw#", "#wwwwww#", "#wwwwww#", "#wwwwww#", "########" }, { ["#"] = "ink", w = "wood_dark", y = "gold" })

------------------------------------------------------------------ lanes: dodge and catch
-- A row of lanes along the bottom with a mover the arrows (or the pads) step from lane to lane; things fall down
-- the lanes. `onHit(item)` decides what touching one does.
type Faller = { f: Frame, lane: number, y: number, good: boolean, gone: boolean }
local function lanes(ctx: Ctx, n: number, mover: PixelSprites.Sprite)
	local s = ctx.px
	local lw = math.min(36, math.floor(ctx.w / (n + 1)))
	local x0 = math.floor((ctx.w - lw * n) / 2)
	for i = 1, n do
		local strip = box(ctx.area, lw - 2, ctx.h - 30, x0 + (i - 1) * lw + 1, 12, "plate_light", 7)
		strip.BackgroundTransparency = 0.55
	end
	local lane = math.ceil(n / 2)
	local my = ctx.h - 22 - 8 * s
	local me = sprite(ctx.area, mover, 0, my, s, 10)
	local function place()
		me.Position = UDim2.fromOffset(x0 + (lane - 1) * lw + math.floor((lw - 8 * s) / 2), my)
	end
	place()
	arrowsPads(ctx, { "left", "right" })
	return {
		lw = lw,
		x0 = x0,
		my = my,
		n = n,
		lane = function(): number
			return lane
		end,
		move = function(d: number)
			lane = math.clamp(lane + d, 1, n)
			place()
		end,
		xOf = function(l: number): number
			return x0 + (l - 1) * lw + math.floor((lw - 8 * s) / 2)
		end,
	}
end

------------------------------------------------------------------ 1. dodge (Action "Dodge!", Racing "Steer!")
function Games.dodge(ctx: Ctx): Micro
	local race = ctx.variant == "race"
	local n = if ctx.diff >= 7 then 5 elseif ctx.diff >= 4 then 4 else 3
	local L = lanes(ctx, n, if race then PixelSprites.ICONS.racing else HERO)
	local s = ctx.px
	local items: { Faller } = {}
	local nextAt = 0.4
	local fall = (46 + 9 * ctx.diff) * ctx.speed
	local every = math.max(0.32, 0.8 - 0.06 * ctx.diff) / ctx.speed
	local dead = false
	local stripes: { Frame } = {}
	if race then
		for i = 1, 4 do
			table.insert(stripes, box(ctx.area, 2, 8, 2, i * 24, "white", 7))
			table.insert(stripes, box(ctx.area, 2, 8, ctx.w - 4, i * 24, "white", 7))
		end
	end
	say(ctx, if race then "Steer clear of the cones!" else "Dodge the blocks!")
	return {
		survive = true,
		update = function(t: number, dt: number)
			if dead then
				return
			end
			for i, st in stripes do
				st.Position = UDim2.fromOffset(st.Position.X.Offset, (i * 24 + t * fall) % (ctx.h - 20))
			end
			if t >= nextAt then
				nextAt = t + every * (0.7 + 0.6 * ctx.rng:next())
				-- never a wall: a lane stays open in every band of the screen
				local busy: { [number]: boolean } = {}
				local nBusy = 0
				for _, it in items do
					if not it.gone and it.y < 12 + 26 * s and not busy[it.lane] then
						busy[it.lane] = true
						nBusy += 1
					end
				end
				local l = ctx.rng:int(1, n)
				if nBusy < n - 1 or busy[l] then
					table.insert(items, { f = sprite(ctx.area, if race then CONE else BLOCK, L.xOf(l), 12, s, 9), lane = l, y = 12, good = false, gone = false })
				end
			end
			for _, it in items do
				if not it.gone then
					it.y += fall * dt
					it.f.Position = UDim2.fromOffset(L.xOf(it.lane), math.floor(it.y))
					if it.lane == L.lane() and it.y + 8 * s > L.my + 2 and it.y < L.my + 8 * s - 2 then
						dead = true
						ctx.shake()
						ctx.lose()
						return
					end
					if it.y > ctx.h - 20 then
						it.gone = true
						it.f:Destroy()
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
					if not it.gone and it.lane == l and it.y < L.my + 8 * s then
						g = math.min(g, L.my - (it.y + 8 * s))
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
function Games.timing(ctx: Ctx): Micro
	local need = if ctx.diff >= 7 then 3 elseif ctx.diff >= 4 then 2 else 1
	local bw = math.min(200, ctx.w - 40)
	local bx, by = math.floor((ctx.w - bw) / 2), math.floor(ctx.h / 2) + 4
	local zoneW = math.max(8, math.floor((40 - 4 * ctx.diff) * ctx.px / 2))
	box(ctx.area, bw + 2, 12, bx - 1, by - 1, "ink", 8)
	box(ctx.area, bw, 10, bx, by, "plate_light", 8)
	local zone = box(ctx.area, zoneW, 10, bx, by, "good", 9)
	local cursor = box(ctx.area, 2, 16, bx, by - 3, "white", 10)
	local pos, dir = 0, 1
	local speed = (70 + 16 * ctx.diff) * ctx.speed
	local hits = 0
	local zx = 0
	local themeIcon = if ctx.variant == "flip" then PixelSprites.ICONS.cooking elseif ctx.variant == "kick" then PixelSprites.ICONS.sports else PixelSprites.ICONS.rpg
	local hero = sprite(ctx.area, themeIcon, ctx.w / 2 - 12, by - 36, 3, 9)
	local count = say(ctx, string.format("Hit the green: 0/%d", need))
	local function placeZone()
		zx = ctx.rng:int(0, bw - zoneW)
		zone.Position = UDim2.fromOffset(bx + zx, by)
	end
	placeZone()
	local done = false
	local function press()
		if done then
			return
		end
		if pos >= zx - 1 and pos <= zx + zoneW + 1 then
			hits += 1
			Audio.play("pop", { pitch = 1 + hits * 0.15 })
			ctx.pop(bx + zx + zoneW / 2, by - 12, if ctx.variant == "kick" then "Goal!" elseif ctx.variant == "strike" then "Crit!" else "Flip!", UIKit.color("good"))
			UIKit.tween(hero, 0.12, { Position = UDim2.fromOffset(ctx.w / 2 - 12, by - 46) })
			task.delay(0.12, function()
				if hero.Parent then
					UIKit.tween(hero, 0.12, { Position = UDim2.fromOffset(ctx.w / 2 - 12, by - 36) })
				end
			end)
			UIKit.setText(count, string.format("Hit the green: %d/%d", hits, need))
			if hits >= need then
				done = true
				ctx.win()
			else
				placeZone()
			end
		else
			done = true
			ctx.shake()
			ctx.lose()
		end
	end
	pad(ctx, "Go!", "go", ctx.w / 2 - 30, ctx.h - 16, 60, 16, "accent")
	return {
		update = function(_t: number, dt: number)
			if done then
				return
			end
			pos += dir * speed * dt
			if pos >= bw - 2 then
				pos, dir = bw - 2, -1
			elseif pos <= 0 then
				pos, dir = 0, 1
			end
			cursor.Position = UDim2.fromOffset(bx + math.floor(pos), by - 3)
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
	local scale = if ctx.px == 1 then 3 else 5
	local pet = Instance.new("TextButton")
	pet.Name = "Pad_go"
	pet.Text = ""
	pet.BackgroundTransparency = 1
	pet.AutoButtonColor = true
	pet.Size = UDim2.fromOffset(8 * scale, 8 * scale)
	pet.Position = UDim2.fromOffset(math.floor(ctx.w / 2 - 4 * scale), math.floor(ctx.h / 2 - 4 * scale))
	pet.ZIndex = 9
	PixelSprites.sprite(pet, PixelSprites.ICONS.animals, nil, scale, 10)
	pet.Activated:Connect(function()
		ctx.press("go")
	end)
	pet.Parent = ctx.area
	local _, setBar = UIKit.bar(ctx.area, UDim2.fromOffset(120, 4), UDim2.fromOffset(math.floor(ctx.w / 2 - 60), ctx.h - 8), UIKit.color("pink"), UIKit.color("plate_light"))
	setBar(0)
	local label = say(ctx, string.format("Pet it! 0/%d", need))
	local done = false
	local function press()
		if done then
			return
		end
		n += 1
		setBar(n / need)
		UIKit.setText(label, string.format("Pet it! %d/%d", n, need))
		Audio.play("pop", { volume = 0.6, pitch = 1 + (n % 5) * 0.06 })
		ctx.pop(ctx.w / 2 + ctx.rng:int(-20, 20), ctx.h / 2 - 4 * scale - 4, "<3", UIKit.color("pink"))
		pet.Position = UDim2.fromOffset(pet.Position.X.Offset, math.floor(ctx.h / 2 - 4 * scale) + (if n % 2 == 0 then 0 else 2))
		if n >= need then
			done = true
			ctx.win()
		end
	end
	return {
		update = function(_t: number, _dt: number) end,
		key = function(_k: string)
			press()
		end,
		auto = function()
			press()
		end,
	}
end

------------------------------------------------------------------ 4. whack (Space "Shoot!", Farming "Water!", Zombies "Whack!")
function Games.whack(ctx: Ctx): Micro
	local cols = if ctx.diff >= 3 then 4 else 3
	local rows = if ctx.diff >= 6 then 3 else 2
	local need = 4 + ctx.diff
	local s = ctx.px
	local cw, ch = 30, 26
	local gx = math.floor((ctx.w - cols * (cw + 6) + 6) / 2)
	local gy = 14 + math.floor((ctx.h - 14 - rows * (ch + 4)) / 2)
	local variant = ctx.variant
	local target = if variant == "space" then ALIEN elseif variant == "water" then SPROUT else PixelSprites.ICONS.zombies
	local decoySprite = if variant == "space" then PixelSprites.ICONS.space elseif variant == "zombie" then KID else nil
	local after = if variant == "water" then FLOWER else nil
	type Hole = { b: TextButton, t: Frame, d: Frame?, untilT: number, decoy: boolean }
	local holes: { Hole } = {}
	local hits = 0
	local now = 0
	local nextAt = 0.2
	local life = math.max(0.45, 1.05 - 0.07 * ctx.diff) / ctx.speed
	local every = math.max(0.25, 0.6 - 0.04 * ctx.diff) / ctx.speed
	local done = false
	local label = say(ctx, string.format("%s 0/%d", if variant == "water" then "Water the dry ones:" elseif variant == "space" then "Shoot the aliens:" else "Whack the zombies:", need))
	local function hit(i: number)
		local hole = holes[i]
		if done then
			return
		end
		if hole.untilT > now then
			hole.untilT = 0
			hole.t.Visible = false
			if hole.d then
				(hole.d :: Frame).Visible = false
			end
			if hole.decoy then
				done = true
				ctx.shake()
				ctx.pop(hole.b.Position.X.Offset + cw / 2, hole.b.Position.Y.Offset, "Oops!", UIKit.color("bad"))
				ctx.lose()
				return
			end
			hits += 1
			Audio.play("squish")
			ctx.pop(hole.b.Position.X.Offset + cw / 2, hole.b.Position.Y.Offset, "+1", UIKit.color("good"))
			UIKit.setText(label, string.format("%s %d/%d", if variant == "water" then "Water the dry ones:" elseif variant == "space" then "Shoot the aliens:" else "Whack the zombies:", hits, need))
			if after then
				local fl = sprite(hole.b, after, math.floor((cw - 8 * s) / 2), ch - 8 * s - 2, s, 11)
				task.delay(0.35, function()
					fl:Destroy()
				end)
			end
			if hits >= need then
				done = true
				ctx.win()
			end
		end
	end
	for i = 1, cols * rows do
		local c, r = (i - 1) % cols, (i - 1) // cols
		local b = Instance.new("TextButton")
		b.Name = "Hole_" .. i
		b.Text = ""
		b.BackgroundTransparency = 1
		b.AutoButtonColor = true
		b.Size = UDim2.fromOffset(cw, ch)
		b.Position = UDim2.fromOffset(gx + c * (cw + 6), gy + r * (ch + 4))
		b.ZIndex = 8
		UIKit.plate(b, UDim2.fromOffset(cw, ch), nil, UIKit.color(if variant == "space" then "sky_night" elseif variant == "water" then "grass_dark" else "steel_dark"), 0, 1).ZIndex = 8
		local t = sprite(b, target, math.floor((cw - 8 * s) / 2), ch - 8 * s - 2, s, 10)
		t.Visible = false
		local d = if decoySprite then sprite(b, decoySprite, math.floor((cw - 8 * s) / 2), ch - 8 * s - 2, s, 10) else nil
		if d then
			d.Visible = false
		end
		b.Activated:Connect(function()
			hit(i)
		end)
		b.Parent = ctx.area
		holes[i] = { b = b, t = t, d = d, untilT = 0, decoy = false }
	end
	return {
		update = function(t: number, _dt: number)
			now = t
			for _, hole in holes do
				if hole.untilT > 0 and hole.untilT <= t then
					hole.untilT = 0
					hole.t.Visible = false
					if hole.d then
						(hole.d :: Frame).Visible = false
					end
				end
			end
			if t >= nextAt and not done then
				nextAt = t + every
				local free = {}
				for i, hole in holes do
					if hole.untilT <= t then
						table.insert(free, i)
					end
				end
				if #free > 0 then
					local hole = holes[free[ctx.rng:int(1, #free)]]
					hole.decoy = decoySprite ~= nil and ctx.diff >= 4 and ctx.rng:chance(0.25)
					hole.untilT = t + life
					if hole.decoy and hole.d then
						(hole.d :: Frame).Visible = true
					else
						hole.decoy = false
						hole.t.Visible = true
					end
				end
			end
		end,
		key = function(_k: string) end,
		auto = function()
			for i, hole in holes do
				if hole.untilT > now and not hole.decoy then
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
	local s = ctx.px
	local function choose(i: number)
		if done then
			return
		end
		done = true
		if i == right then
			Audio.play("ding")
			ctx.win()
		else
			ctx.shake()
			ctx.lose()
		end
	end
	local movers: { { f: Frame, vx: number, vy: number } } = {}
	if variant == "spot" then
		-- a grid of one icon, one of them in another colour: tap it
		local cols = if ctx.diff >= 6 then 6 elseif ctx.diff >= 3 then 5 else 4
		local rows = if ctx.diff >= 6 then 4 else 3
		local icon = PixelSprites.ICONS[({ "detectives", "pirates", "horror", "robots" })[ctx.rng:int(1, 4)]]
		local odd: { [string]: string } = {}
		for ch, col in icon.colors do
			odd[ch] = if ch == "#" then "ink" else (if col == "pink" then "purple" else "pink")
		end
		right = ctx.rng:int(1, cols * rows)
		local cell = 8 * s + 6
		local gx = math.floor((ctx.w - cols * cell) / 2)
		local gy = 14
		for i = 1, cols * rows do
			local c, r = (i - 1) % cols, (i - 1) // cols
			local b = Instance.new("TextButton")
			b.Name = "Opt_" .. i
			b.Text = ""
			b.BackgroundTransparency = 1
			b.AutoButtonColor = true
			b.Size = UDim2.fromOffset(cell - 2, cell - 2)
			b.Position = UDim2.fromOffset(gx + c * cell, gy + r * cell)
			b.ZIndex = 8
			UIKit.plate(b, UDim2.fromScale(1, 1), nil, UIKit.color("plate_light"), 0, 1).ZIndex = 8
			PixelSprites.draw(b, icon.rows, if i == right then odd else icon.colors, UDim2.fromOffset(2, 2), s, 9)
			b.Activated:Connect(function()
				choose(i)
			end)
			b.Parent = ctx.area
		end
		say(ctx, "Spot the odd one out!")
		return {
			update = function(_t: number, _dt: number) end,
			key = function(_k: string) end,
			auto = function()
				choose(right)
			end,
		}
	end
	-- a question at the top, n options along the bottom (keys 1..n)
	local labels: { string } = {}
	local icons: { PixelSprites.Sprite } = {}
	if variant == "match" then
		local pool = { "action", "puzzle", "animals", "space", "cooking", "school", "racing", "pirates", "ocean", "rpg", "fantasy", "robots", "ninjas", "zombies", "horror", "music" }
		for i = #pool, 2, -1 do
			local j = ctx.rng:int(1, i)
			pool[i], pool[j] = pool[j], pool[i]
		end
		right = ctx.rng:int(1, n)
		for i = 1, n do
			icons[i] = PixelSprites.ICONS[pool[i]]
		end
		say(ctx, "Which one matches?")
		local target = icons[right]
		box(ctx.area, 8 * 3 + 6, 8 * 3 + 6, ctx.w / 2 - 15, 12, "paper", 8)
		sprite(ctx.area, target, ctx.w / 2 - 12, 15, 3, 9)
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
			UIKit.text(ctx.area, q, UDim2.fromOffset(ctx.w, 18), UDim2.fromOffset(0, 18), { x = "center", face = "big", color = UIKit.color("text"), z = 10, name = "Question" })
		else
			-- count: soldiers scattered over the field (moving from difficulty 5)
			answer = ctx.rng:int(3, 5 + ctx.diff)
			q = "How many soldiers?"
			for _ = 1, answer do
				local f = sprite(ctx.area, HERO, ctx.rng:int(10, ctx.w - 10 - 8 * s), ctx.rng:int(12, ctx.h - 40 - 8 * s), s, 9)
				if ctx.diff >= 5 then
					table.insert(movers, { f = f, vx = (ctx.rng:next() - 0.5) * 50, vy = (ctx.rng:next() - 0.5) * 30 })
				end
			end
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
	local ow = math.min(36, math.floor((ctx.w - 8) / n) - 4)
	local total = n * (ow + 4) - 4
	for i = 1, n do
		local b = UIKit.button(ctx.area, labels[i] or "", UDim2.fromOffset(ow, if variant == "match" then 28 else 18), UDim2.fromOffset(math.floor((ctx.w - total) / 2) + (i - 1) * (ow + 4), ctx.h - (if variant == "match" then 28 else 18)), function()
			choose(i)
		end, { name = "Opt_" .. i, color = UIKit.color("plate_light"), face = if variant == "match" then nil else "big" })
		b.ZIndex = 10
		if icons[i] then
			PixelSprites.sprite(b, icons[i], UDim2.fromOffset(math.floor((ow - 8 * s) / 2), math.floor((28 - 8 * s) / 2)), s, 11)
		end
	end
	return {
		update = function(_t: number, dt: number)
			for _, m in movers do
				local p = m.f.Position
				local x, y = p.X.Offset + m.vx * dt * ctx.speed, p.Y.Offset + m.vy * dt * ctx.speed
				if x < 4 or x > ctx.w - 20 then
					m.vx = -m.vx
				end
				if y < 12 or y > ctx.h - 48 then
					m.vy = -m.vy
				end
				m.f.Position = UDim2.fromOffset(math.clamp(x, 4, ctx.w - 20), math.clamp(y, 12, ctx.h - 48))
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
		for i = 1, 4 do
			local b = pad(ctx, tostring(i), tostring(i), (ctx.w - total) / 2 + (i - 1) * (pw + 6), ctx.h / 2 - 12, pw, 30, "plate_light")
			pads[i] = b
		end
		local label = say(ctx, "Watch...")
		local step = 0.5 / ctx.speed
		local showing = true
		local at = 1
		local done = false
		local lit = 0
		local function light(i: number, on: boolean)
			UIKit.setButtonColor(pads[i], if on then UIKit.color(colors[i]) else UIKit.color("plate_light"))
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
	local len = 3 + math.floor(ctx.diff / 2)
	local seq: { string } = {}
	for i = 1, len do
		seq[i] = DIRS[ctx.rng:int(1, 4)]
	end
	local tiles: { { p: Frame, a: Frame } } = {}
	local tw = math.min(20, math.floor((ctx.w - 10) / len) - 3)
	local total = len * (tw + 3) - 3
	for i = 1, len do
		local p = UIKit.plate(ctx.area, UDim2.fromOffset(tw, 20), UDim2.fromOffset(math.floor((ctx.w - total) / 2) + (i - 1) * (tw + 3), 24), UIKit.color("plate_light"), 0, 2)
		p.ZIndex = 8
		local a = PixelSprites.draw(p, PixelSprites.ARROWS[seq[i]], { ["#"] = "text" }, UDim2.fromOffset(math.floor((tw - 7 * ctx.px / 2) / 2), 6), math.max(1, ctx.px // 2), 9)
		tiles[i] = { p = p, a = a }
	end
	local hideAt = if ctx.variant == "program" and ctx.diff >= 4 then 1.2 / ctx.speed else math.huge
	local hidden = false
	local at = 1
	local done = false
	say(ctx, if ctx.variant == "program" then "Program the robot!" else "Cast the spell!")
	local function highlight()
		for i, tl in ipairs(tiles) do
			UIKit.setPlate(tl.p, if i < at then UIKit.color("good") elseif i == at then UIKit.color("button") else UIKit.color("plate_light"))
		end
	end
	highlight()
	arrowsPads(ctx, { "left", "up", "down", "right" })
	local function typeKey(k: string)
		if done or table.find(DIRS, k) == nil then
			return
		end
		if k == seq[at] then
			tiles[at].a.Visible = true
			Audio.play("key")
			at += 1
			highlight()
			if at > len then
				done = true
				ctx.win()
			end
		else
			done = true
			UIKit.setPlate(tiles[at].p, UIKit.color("bad"))
			ctx.shake()
			ctx.lose()
		end
	end
	return {
		update = function(t: number, _dt: number)
			if not hidden and t >= hideAt then
				hidden = true
				for _, tl in tiles do
					tl.a.Visible = false
				end
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
	local L = lanes(ctx, n, BASKET)
	local s = ctx.px
	local need = 3 + math.floor(ctx.diff / 2)
	local got = 0
	local items: { Faller } = {}
	local nextAt = 0.3
	local fall = (42 + 8 * ctx.diff) * ctx.speed
	local every = math.max(0.3, 0.7 - 0.05 * ctx.diff) / ctx.speed
	local badShare = math.min(0.5, 0.2 + 0.04 * ctx.diff)
	local done = false
	local label = say(ctx, string.format("%s 0/%d", if fish then "Catch fish, not jellies:" else "Grab coins, not bombs:", need))
	return {
		update = function(t: number, dt: number)
			if done then
				return
			end
			if t >= nextAt then
				nextAt = t + every * (0.7 + 0.6 * ctx.rng:next())
				local l = ctx.rng:int(1, n)
				local good = not ctx.rng:chance(badShare)
				local spr = if good then (if fish then FISH else COIN) else (if fish then JELLY else BOMB)
				table.insert(items, { f = sprite(ctx.area, spr, L.xOf(l), 12, s, 9), lane = l, y = 12, good = good, gone = false })
			end
			for _, it in items do
				if not it.gone then
					it.y += fall * dt
					it.f.Position = UDim2.fromOffset(L.xOf(it.lane), math.floor(it.y))
					if it.lane == L.lane() and it.y + 8 * s > L.my + 2 and it.y < L.my + 4 then
						it.gone = true
						it.f:Destroy()
						if it.good then
							got += 1
							Audio.play("coin")
							ctx.pop(L.xOf(it.lane) + 4 * s, L.my - 6, "+1", UIKit.color("accent"))
							UIKit.setText(label, string.format("%s %d/%d", if fish then "Catch fish, not jellies:" else "Grab coins, not bombs:", got, need))
							if got >= need then
								done = true
								ctx.win()
								return
							end
						else
							done = true
							ctx.shake()
							ctx.lose()
							return
						end
					elseif it.y > ctx.h - 20 then
						it.gone = true
						it.f:Destroy()
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
					if not it.gone and not it.good and it.lane == l and it.y > L.my - 8 * s - 30 and it.y < L.my + 4 then
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
	local s = ctx.px
	local ground = ctx.h - 22
	box(ctx.area, ctx.w, 2, 0, ground, if dino then "wood" else "leaf_dark", 8)
	local px0 = 30
	local me = sprite(ctx.area, if dino then PixelSprites.ICONS.dinosaurs else HERO, px0, ground - 8 * s, s, 10)
	type Ob = { f: Frame, x: number, gone: boolean }
	local obs: { Ob } = {}
	local speed = (70 + 11 * ctx.diff) * ctx.speed
	local nextAt = 0.6
	local jumpT = -1
	local JUMP = 0.62 / ctx.speed
	local H = 26 + 4 * s
	local y = 0
	local dead = false
	pad(ctx, "Jump!", "go", ctx.w - 64, ctx.h - 16, 60, 16, "accent")
	say(ctx, if dino then "Jump the cacti!" else "Leap over the rocks!")
	local now = 0
	local function jump()
		if jumpT < 0 and not dead then
			jumpT = now
			Audio.play("pop", { pitch = 1.3 })
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
					y = 0
				else
					y = math.floor(4 * H * k * (1 - k))
				end
			end
			me.Position = UDim2.fromOffset(px0, ground - 8 * s - y)
			if t >= nextAt then
				nextAt = t + math.max(0.55, (1.25 - 0.06 * ctx.diff)) / ctx.speed * (0.8 + 0.5 * ctx.rng:next())
				table.insert(obs, { f = sprite(ctx.area, if dino then CACTUS else ROCK, ctx.w, ground - 8 * s, s, 9), x = ctx.w, gone = false })
			end
			for _, o in obs do
				if not o.gone then
					o.x -= speed * dt
					o.f.Position = UDim2.fromOffset(math.floor(o.x), ground - 8 * s)
					if o.x < px0 + 8 * s - 3 and o.x + 8 * s - 3 > px0 and y < 8 * s - 3 then
						dead = true
						ctx.shake()
						ctx.lose()
						return
					end
					if o.x < -10 then
						o.gone = true
						o.f:Destroy()
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
				if not o.gone and o.x > px0 and o.x - px0 < 8 * s + speed * 0.12 then
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
	type Note = { t: number, lane: number, f: Frame?, judged: boolean }
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
	for l = 1, nLanes do
		local strip = box(ctx.area, lw, hitY - 8, x0 + (l - 1) * (lw + 4), 12, "plate_light", 7)
		strip.BackgroundTransparency = 0.5
		pad(ctx, tostring(l), tostring(l), x0 + (l - 1) * (lw + 4), ctx.h - 16, lw, 16, "sound")
	end
	box(ctx.area, nLanes * (lw + 4), 2, x0 - 2, hitY, "white", 9)
	local misses = 0
	local now = 0
	local done = false
	local label = say(ctx, string.format("Tap on the line! Misses %d/%d", 0, allowed))
	local function miss()
		misses += 1
		UIKit.setText(label, string.format("Tap on the line! Misses %d/%d", misses, allowed))
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
			if b.f then
				(b.f :: Frame):Destroy()
			end
			Audio.play("tick", { pitch = 0.9 + l * 0.15 })
			ctx.pop(x0 + (l - 1) * (lw + 4) + lw / 2, hitY - 12, if math.abs(b.t - now) < win / 2 then "Perfect!" else "Good", UIKit.color("accent"))
		else
			miss()
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
						if n.f then
							(n.f :: Frame):Destroy()
						end
						miss()
					elseif dt <= travel then
						local yy = hitY - math.floor(dt / travel * (hitY - 14)) - 6
						if n.f == nil then
							n.f = sprite(ctx.area, PixelSprites.NOTE, 0, 0, ctx.px, 10)
						end
						(n.f :: Frame).Position = UDim2.fromOffset(x0 + (n.lane - 1) * (lw + 4) + math.floor((lw - 6 * ctx.px) / 2), yy)
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
	local s = ctx.px
	local need = 4 + math.floor(ctx.diff / 2)
	local got = 0
	type Fly = { b: TextButton, x: number, y: number, vx: number, vy: number, bomb: boolean, gone: boolean }
	local flies: { Fly } = {}
	local nextAt = 0.2
	local every = math.max(0.3, 0.75 - 0.05 * ctx.diff) / ctx.speed
	local g = 150 * ctx.speed * ctx.speed
	local done = false
	local k = 0
	local label = say(ctx, string.format("Slice the fruit, not the bombs! 0/%d", need))
	local function cut(f: Fly)
		if done or f.gone then
			return
		end
		f.gone = true
		f.b:Destroy()
		if f.bomb then
			done = true
			ctx.shake()
			ctx.pop(f.x, f.y, "Boom!", UIKit.color("bad"))
			ctx.lose()
			return
		end
		got += 1
		Audio.play("squish", { pitch = 1.2 })
		ctx.pop(f.x, f.y, "Slice!", UIKit.color("good"))
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
				local b = Instance.new("TextButton")
				b.Name = (if bomb then "Bomb_" else "Fruit_") .. k
				b.Text = ""
				b.BackgroundTransparency = 1
				b.AutoButtonColor = false
				b.Size = UDim2.fromOffset(8 * s + 6, 8 * s + 6)
				b.ZIndex = 9
				PixelSprites.sprite(b, if bomb then BOMB else FRUIT, UDim2.fromOffset(3, 3), s, 10)
				b.Parent = ctx.area
				local fl: Fly = { b = b, x = ctx.rng:int(20, ctx.w - 30), y = ctx.h, vx = (ctx.rng:next() - 0.5) * 60 * ctx.speed, vy = -(130 + ctx.rng:next() * 40) * ctx.speed, bomb = bomb, gone = false }
				b.Activated:Connect(function()
					cut(fl)
				end)
				table.insert(flies, fl)
			end
			for _, f in flies do
				if not f.gone then
					f.vy += g * dt
					f.x += f.vx * dt
					f.y += f.vy * dt
					f.b.Position = UDim2.fromOffset(math.floor(f.x), math.floor(f.y))
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
	local s = ctx.px
	local steps = 5 + ctx.diff
	local at = 0
	local x0, x1 = 16, ctx.w - 60
	local floorY = ctx.h - 24
	box(ctx.area, ctx.w, 2, 0, floorY, "plate_light", 8)
	sprite(ctx.area, DOOR, x1 + 8, floorY - 8 * 3, 3, 8)
	local me = sprite(ctx.area, KID, x0, floorY - 8 * s, s, 10)
	local ghost = sprite(ctx.area, PixelSprites.ICONS.horror, ctx.w / 2 - 12, 14, 3, 9)
	local glare = PixelSprites.draw(ctx.area, PixelSprites.ICONS.horror.rows, { ["#"] = "ink", w = "bad" }, UDim2.fromOffset(math.floor(ctx.w / 2 - 12), 18), 3, 9)
	glare.Visible = false
	local eyes = say(ctx, "Sneak while it looks away!")
	local state = "away" -- "away" | "warn" | "watch"
	local untilT = 0.8 + ctx.rng:next()
	local done = false
	local now = 0
	local warnT = math.max(0.25, 0.55 - 0.04 * ctx.diff) / ctx.speed
	local function step()
		if done then
			return
		end
		if state == "watch" then
			done = true
			ctx.shake()
			ctx.pop(x0 + (x1 - x0) * at / steps, floorY - 20, "Seen!", UIKit.color("bad"))
			ctx.lose()
			return
		end
		at += 1
		Audio.play("key", { pitch = 0.8 })
		me.Position = UDim2.fromOffset(math.floor(x0 + (x1 - x0) * at / steps), floorY - 8 * s)
		if at >= steps then
			done = true
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
			ghost.Position = UDim2.fromOffset(math.floor(ctx.w / 2 - 12 + jig), 14)
			ghost.Visible = state ~= "watch"
			glare.Visible = state == "watch"
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
function Games.stack(ctx: Ctx): Micro
	local need = 3 + math.floor(ctx.diff / 2)
	local bh = 8
	local baseY = ctx.h - 22
	local w = math.floor(60 * ctx.px / 2) + 10
	local topX = math.floor((ctx.w - w) / 2)
	box(ctx.area, w, bh, topX, baseY - bh, "steel", 8)
	local level = 1
	local moving = box(ctx.area, w, bh, 0, baseY - bh * 2, "blue", 9)
	local mx, dir = 0, 1
	local speed = (60 + 12 * ctx.diff) * ctx.speed
	local done = false
	local label = say(ctx, string.format("Drop the floors! 0/%d", need))
	local function drop()
		if done then
			return
		end
		local left = math.max(mx, topX)
		local right = math.min(mx + w, topX + w)
		local overlap = right - left
		if overlap <= 0 then
			done = true
			ctx.shake()
			ctx.lose()
			return
		end
		Audio.play("pop", { pitch = 0.8 + level * 0.1 })
		moving.Size = UDim2.fromOffset(overlap, bh)
		moving.Position = UDim2.fromOffset(left, baseY - bh * (level + 1))
		box(ctx.area, 2, 2, left + 2, baseY - bh * (level + 1) + 3, "window", 10)
		topX, w = left, overlap
		UIKit.setText(label, string.format("Drop the floors! %d/%d", level, need))
		if level >= need then
			done = true
			ctx.win()
			return
		end
		level += 1
		moving = box(ctx.area, w, bh, 0, baseY - bh * (level + 1), "blue", 9)
		mx, dir = if ctx.rng:chance(0.5) then 0 else ctx.w - w, if ctx.rng:chance(0.5) then 1 else -1
	end
	pad(ctx, "Drop!", "go", ctx.w - 64, ctx.h - 16, 60, 16, "accent")
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
