--!strict
-- The five minigames (GAME_DESIGN 14; docs/ARCHITECTURE.md 10.8), each built into MinigameUI's play area: Code Rush
-- (type the arrows as they come), Idea Match (find the pairs), Pixel Paint (paint the sprite to match), Beat Keeper
-- (tap as each note hits the line) and Bug Squash (tap the bugs before they hide). A game gets the area, its size and
-- an Rng seeded by the server, and answers MinigameUI's clock (update), the keys it maps (key) and its score so far
-- (0-100). Everything is UI px on the pixel grid; every button a sim can press has a name (Key_<dir>, Card_<i>,
-- Cell_<r>_<c>, Swatch_<i>, Pad_<lane>, Hole_<i>).
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
	seconds: number,
	pop: (x: number, y: number, text: string, color: Color3) -> (), -- a word floating up in the area
	shake: () -> (), -- the card shakes (a wrong key)
}

export type Game = {
	hint: string, -- the controls, under the area
	update: (t: number, dt: number) -> (), -- t: seconds since the start
	key: (name: string) -> (), -- "up" | "down" | "left" | "right" | "lane1" | "lane2" | "1" | "2" | "3"
	score: () -> number, -- 0..100 so far
	progress: () -> string, -- a short tally (lines, pairs, bugs...)
	done: () -> boolean, -- finished before the clock ran out
	auto: () -> (), -- one right move (the sims' and the previews' player; the score is the client's word anyway)
}

local Games = {}

local function clamp100(x: number): number
	return math.clamp(math.floor(x + 0.5), 0, 100)
end

-- A plain square cell button (no plate, no words): Pixel Paint's canvas, Idea Match's hit boxes.
local function cell(parent: Instance, name: string, size: UDim2, pos: UDim2, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Text = ""
	b.AutoButtonColor = true
	b.BorderSizePixel = 0
	b.BackgroundColor3 = color
	b.Size = size
	b.Position = pos
	b.ZIndex = 8
	b.Activated:Connect(function()
		onClick()
	end)
	b.Parent = parent
	return b
end

------------------------------------------------------------------ Code Rush (Fun)
local DIRS = { "up", "right", "down", "left" }
local CODE_ROW = 6
local CODE_TARGET = 26 -- right keys (less wrong ones) for a score of 100
local CODE_COLORS = { "fun", "ideas", "graphics", "sound", "text_dim", "button" }

function Games.code(ctx: Ctx): Game
	local area, w, h, rng = ctx.area, ctx.w, ctx.h, ctx.rng
	local correct, wrong, lines = 0, 0, 0
	local seq: { string } = {}
	local idx = 1
	local tiles: { { plate: Frame, arrow: Frame } } = {}
	local rowFrame: Frame? = nil
	local TILE, GAP = 20, 4
	local rowW = CODE_ROW * (TILE + GAP) - GAP
	local rowX = math.floor((w - rowW) / 2)

	-- the editor: a line of code bars for every row typed (the newest four)
	local edW, edH = math.min(170, w - 20), math.max(34, h - 30 - 30)
	local edRows = math.max(4, (edH - 6) // 7)
	local editor = UIKit.plate(area, UDim2.fromOffset(edW, edH), UDim2.fromOffset(math.floor((w - edW) / 2), 30), UIKit.color("ink"), 0, 2)
	editor.Name = "Editor"
	editor.ZIndex = 7
	local edLines: { Frame } = {}
	local function addCodeLine()
		local line = Instance.new("Frame")
		line.Name = "CodeLine"
		line.BackgroundTransparency = 1
		line.Size = UDim2.fromOffset(edW - 8, 4)
		line.ZIndex = 8
		local x = 2 + 6 * (rng:int(0, 2))
		for _ = 1, rng:int(2, 4) do
			local bw = rng:int(6, 22)
			if x + bw > edW - 10 then
				break
			end
			UIKit.rect(line, UDim2.fromOffset(bw, 3), UDim2.fromOffset(x, 0), UIKit.color(CODE_COLORS[rng:int(1, #CODE_COLORS)]), 9)
			x += bw + 3
		end
		line.Parent = editor
		table.insert(edLines, line)
		while #edLines > edRows do
			local old = table.remove(edLines, 1)
			if old then
				old:Destroy()
			end
		end
		for i, l in edLines do
			l.Position = UDim2.fromOffset(4, 4 + (i - 1) * 7)
		end
	end
	addCodeLine()

	local function highlight()
		for i, tile in tiles do
			if i == idx then
				UIKit.setPlate(tile.plate, UIKit.color("button"))
				PixelSprites.tint(tile.arrow, UIKit.color("white"))
			elseif i > idx then
				UIKit.setPlate(tile.plate, UIKit.color("plate_light"))
				PixelSprites.tint(tile.arrow, UIKit.color("text_dim"))
			end
		end
	end

	local function newRow()
		if rowFrame then
			rowFrame:Destroy()
		end
		local f = Instance.new("Frame")
		f.Name = "Row"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromOffset(rowW, TILE)
		f.Position = UDim2.fromOffset(rowX + 24, 4)
		f.ZIndex = 7
		table.clear(tiles)
		for i = 1, CODE_ROW do
			seq[i] = DIRS[rng:int(1, 4)]
			local p = UIKit.plate(f, UDim2.fromOffset(TILE, TILE), UDim2.fromOffset((i - 1) * (TILE + GAP), 0), UIKit.color("plate_light"), 0, 2)
			p.Name = "Tile"
			p.ZIndex = 8
			local a = PixelSprites.draw(p, PixelSprites.ARROWS[seq[i]], { ["#"] = "text" }, UDim2.fromOffset(3, 3), 2, 9)
			tiles[i] = { plate = p, arrow = a }
		end
		f.Parent = area
		rowFrame = f
		idx = 1
		highlight()
		UIKit.tween(f, 0.12, { Position = UDim2.fromOffset(rowX, 4) })
	end
	newRow()

	local function press(dir: string)
		if idx > CODE_ROW then
			return
		end
		local tile = tiles[idx]
		if dir == seq[idx] then
			correct += 1
			UIKit.setPlate(tile.plate, UIKit.color("good"))
			PixelSprites.tint(tile.arrow, UIKit.color("ink"))
			Audio.play("key")
			idx += 1
			if idx > CODE_ROW then
				lines += 1
				addCodeLine()
				ctx.pop(math.floor(w / 2), 26, "+1 line!", UIKit.color("fun"))
				Audio.play("ding")
				task.delay(0.08, function()
					if area.Parent then
						newRow()
					end
				end)
			else
				highlight()
			end
		else
			wrong += 1
			UIKit.setPlate(tile.plate, UIKit.color("bad"))
			ctx.shake()
			Audio.play("deny")
			task.delay(0.15, function()
				if tile.plate.Parent and tiles[idx] == tile then
					highlight()
				end
			end)
		end
	end

	-- the touch pads (and the mouse): four arrow buttons along the bottom
	local PAD_W, PAD_H = 28, 20
	local padsW = 4 * (PAD_W + 4) - 4
	for i, dir in { "left", "up", "down", "right" } do
		local b = UIKit.button(area, "", UDim2.fromOffset(PAD_W, PAD_H), UDim2.fromOffset(math.floor((w - padsW) / 2) + (i - 1) * (PAD_W + 4), h - PAD_H), function()
			press(dir)
		end, { name = "Key_" .. dir, color = UIKit.color("plate_light") })
		b.ZIndex = 8
		PixelSprites.draw(b, PixelSprites.ARROWS[dir], { ["#"] = "text" }, UDim2.fromOffset(math.floor((PAD_W - 14) / 2), math.floor((PAD_H - 14) / 2)), 2, 9)
	end

	return {
		hint = "Arrows / WASD, or tap the pads",
		update = function(_t: number, _dt: number) end,
		key = function(name: string)
			if name == "up" or name == "down" or name == "left" or name == "right" then
				press(name)
			end
		end,
		score = function(): number
			return clamp100((correct - wrong) * 100 / CODE_TARGET)
		end,
		progress = function(): string
			return string.format("Lines %d", lines)
		end,
		done = function(): boolean
			return false
		end,
		auto = function()
			if seq[idx] then
				press(seq[idx])
			end
		end,
	}
end

------------------------------------------------------------------ Idea Match (Ideas)
local PEEK = 1.6 -- seconds every card shows at the start
local PAIRS = 6

function Games.ideas(ctx: Ctx): Game
	local area, w, h, rng = ctx.area, ctx.w, ctx.h, ctx.rng
	local deck: { number } = {}
	for k = 1, PAIRS do
		table.insert(deck, k)
		table.insert(deck, k)
	end
	for i = #deck, 2, -1 do
		local j = rng:int(1, i)
		deck[i], deck[j] = deck[j], deck[i]
	end
	local CARD, GAP = 26, 4
	local gw, gh = 4 * (CARD + GAP) - GAP, 3 * (CARD + GAP) - GAP
	local x0, y0 = math.floor((w - gw) / 2), math.max(0, math.floor((h - gh) / 2))
	type Card = { button: TextButton, plate: Frame, face: Frame, back: Frame, up: boolean, matched: boolean, x: number, y: number, flip: number }
	local cards: { Card } = {}
	local first: number? = nil
	local hideAt: number? = nil
	local hidePair: { number } = {}
	local pairs, misses = 0, 0
	local finishedAt: number? = nil
	local now = 0
	local peeked = false

	local function show(c: Card, up: boolean, animate: boolean)
		c.up = up
		local function swap()
			c.face.Visible = up
			c.back.Visible = not up
			UIKit.setPlate(c.plate, if c.matched then UIKit.color("good") elseif up then UIKit.color("paper") else UIKit.color("plate_light"))
		end
		if not animate then
			swap()
			return
		end
		-- a flip: the card narrows to a sliver, turns, and widens again (from its own place: a flip may start while
		-- the last one is still running)
		local b = c.button
		c.flip += 1
		local mine = c.flip
		c.face.Visible = false
		c.back.Visible = false
		UIKit.tween(b, 0.06, { Size = UDim2.fromOffset(2, CARD), Position = UDim2.fromOffset(c.x + CARD / 2 - 1, c.y) })
		task.delay(0.06, function()
			if b.Parent == nil or c.flip ~= mine then
				return
			end
			swap()
			UIKit.tween(b, 0.06, { Size = UDim2.fromOffset(CARD, CARD), Position = UDim2.fromOffset(c.x, c.y) })
		end)
	end

	local function tap(i: number)
		local c = cards[i]
		if not peeked or c.matched or c.up or hideAt ~= nil or finishedAt ~= nil then
			return
		end
		show(c, true, true)
		Audio.play("flip")
		local f = first
		if f == nil then
			first = i
			return
		end
		first = nil
		if deck[f] == deck[i] then
			pairs += 1
			cards[f].matched = true
			c.matched = true
			UIKit.setPlate(cards[f].plate, UIKit.color("good"))
			UIKit.setPlate(c.plate, UIKit.color("good"))
			ctx.pop(c.x + CARD / 2, c.y, "Pair!", UIKit.color("ideas"))
			Audio.play(if pairs == PAIRS then "combo" else "ding")
			if pairs == PAIRS then
				finishedAt = now
			end
		else
			misses += 1
			hideAt = now + 0.55
			hidePair = { f, i }
		end
	end

	for i, idea in deck do
		local col, row = (i - 1) % 4, (i - 1) // 4
		local pos = UDim2.fromOffset(x0 + col * (CARD + GAP), y0 + row * (CARD + GAP))
		local b = Instance.new("TextButton")
		b.Name = "Card_" .. i
		b.Text = ""
		b.AutoButtonColor = true
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.Size = UDim2.fromOffset(CARD, CARD)
		b.Position = pos
		b.ZIndex = 8
		b.ClipsDescendants = true
		local plate = UIKit.plate(b, UDim2.fromScale(1, 1), nil, UIKit.color("paper"), 0, 2)
		plate.ZIndex = 8
		local face = PixelSprites.sprite(b, PixelSprites.IDEAS[idea], UDim2.fromOffset(5, 5), 2, 9)
		face.Name = "Face"
		local back = UIKit.text(b, "?", UDim2.fromScale(1, 1), nil, { x = "center", face = "big", color = UIKit.color("text_dim"), z = 9, name = "Back" }) :: any
		back.Visible = false
		b.Activated:Connect(function()
			tap(i)
		end)
		b.Parent = area
		cards[i] = { button = b, plate = plate, face = face, back = back, up = true, matched = false, x = pos.X.Offset, y = pos.Y.Offset, flip = 0 }
	end

	return {
		hint = "Remember them, then find the pairs",
		update = function(t: number, _dt: number)
			now = t
			if not peeked and t >= PEEK then
				peeked = true
				for _, c in cards do
					show(c, false, true)
				end
				Audio.play("flip")
			end
			local at = hideAt
			if at and t >= at then
				hideAt = nil
				for _, k in hidePair do
					show(cards[k], false, true)
				end
			end
		end,
		key = function(_name: string) end,
		score = function(): number
			local bonus = 0
			local fa = finishedAt
			if fa then
				bonus = math.min(16, (ctx.seconds - fa) * 2)
			end
			return clamp100(pairs * 14 + bonus)
		end,
		progress = function(): string
			return string.format("Pairs %d/%d", pairs, PAIRS)
		end,
		done = function(): boolean
			return finishedAt ~= nil
		end,
		auto = function()
			if not peeked or hideAt ~= nil then
				return
			end
			local f = first
			for i, c in cards do
				if not c.matched and not c.up and (f == nil or (i ~= f and deck[i] == deck[f])) then
					if f == nil then
						-- the first of a pair whose partner is also face down
						for j, d in cards do
							if j ~= i and deck[j] == deck[i] and not d.matched then
								tap(i)
								return
							end
						end
					else
						tap(i)
						return
					end
				end
			end
		end,
	}
end

------------------------------------------------------------------ Pixel Paint (Graphics)
type Target = { rows: { string }, a: string, b: string? }
local TARGETS: { Target } = {
	{ rows = { ".a.a.", "aaaaa", ".aaa.", "..a..", "....." }, a = "berry_red" }, -- a heart
	{ rows = { "..a..", ".aaa.", "aaaaa", "..b..", "..b.." }, a = "leaf", b = "wood" }, -- a tree
	{ rows = { "....a", "...a.", "b.a..", ".b...", "b.b.." }, a = "steel", b = "wood" }, -- a sword
	{ rows = { ".aaa.", "aabaa", "..b..", ".bbb.", "....." }, a = "berry_red", b = "cream" }, -- a mushroom
	{ rows = { "..b..", ".aaa.", ".aaa.", ".....", "....." }, a = "purple", b = "steel" }, -- a potion
	{ rows = { ".aaa.", "abaaa", ".aaa.", "..a..", "....." }, a = "screen_on", b = "white" }, -- a gem
	{ rows = { "aa...", "aaaaa", "aa.a.", ".....", "....." }, a = "gold" }, -- a key
	{ rows = { "b...b", ".aaa.", "aaaaa", ".a.a.", "....." }, a = "orange", b = "ink" }, -- a crab
}
local DECOYS = { "blue", "green", "pink", "yellow" }
local PAINT_SPRITES = 2 -- sprites for a score of 100

function Games.pixels(ctx: Ctx): Game
	local area, w, h, rng = ctx.area, ctx.w, ctx.h, ctx.rng
	local order: { number } = {}
	for i = 1, #TARGETS do
		table.insert(order, i)
	end
	for i = #order, 2, -1 do
		local j = rng:int(1, i)
		order[i], order[j] = order[j], order[i]
	end
	local CELL = math.clamp(math.floor((h - 8) / 5), 12, 17)
	local cw = CELL * 5
	local cx, cy = math.floor((w - cw) / 2), math.floor((h - cw) / 2)
	local done, nth = 0, 1
	local target: Target = TARGETS[order[1]]
	local paint: { { string } } = {}
	local cells: { { TextButton } } = {}
	local swatchKeys: { string } = {}
	local swatches: { TextButton } = {}
	local selected = 1
	local preview: Frame? = nil
	local busy = false

	-- the canvas: a grid of cells on an ink board
	local board = UIKit.rect(area, UDim2.fromOffset(cw + 1, cw + 1), UDim2.fromOffset(cx - 1, cy - 1), UIKit.color("ink"), 7)
	board.Name = "Board"
	local function refreshSwatches()
		for i, s in swatches do
			local ring = s:FindFirstChild("Ring")
			if ring and ring:IsA("Frame") then
				ring.Visible = i == selected
			end
		end
	end

	local function drawPreview()
		if preview then
			preview:Destroy()
		end
		local colors: { [string]: string } = { a = target.a, b = target.b or target.a }
		local f = Instance.new("Frame")
		f.Name = "Preview"
		f.BackgroundTransparency = 1
		f.Size = UDim2.fromOffset(40, 50)
		f.Position = UDim2.fromOffset(math.max(2, cx - 52), cy)
		f.ZIndex = 7
		UIKit.text(f, "Paint", UDim2.fromOffset(40, 10), UDim2.fromOffset(0, 0), { color = UIKit.color("text_dim"), z = 8 })
		UIKit.rect(f, UDim2.fromOffset(32, 32), UDim2.fromOffset(0, 12), UIKit.color("paper"), 8)
		PixelSprites.draw(f, target.rows, colors, UDim2.fromOffset(1, 13), 6, 9)
		f.Parent = area
		preview = f
	end

	local function setTarget(t: Target)
		target = t
		local keys = { t.a }
		if t.b then
			table.insert(keys, t.b)
		end
		-- a decoy colour the sprite does not use
		for _ = 1, 8 do
			local d = DECOYS[rng:int(1, #DECOYS)]
			if d ~= t.a and d ~= t.b then
				table.insert(keys, d)
				break
			end
		end
		swatchKeys = keys
		for i, s in swatches do
			s.Visible = keys[i] ~= nil
			if keys[i] then
				local fill = s:FindFirstChild("Fill")
				if fill and fill:IsA("Frame") then
					fill.BackgroundColor3 = UIKit.color(keys[i])
				end
			end
		end
		selected = 1
		refreshSwatches()
		for r = 1, 5 do
			for c = 1, 5 do
				paint[r][c] = "."
				cells[r][c].BackgroundColor3 = UIKit.color("paper")
			end
		end
		drawPreview()
	end

	local function tally(): (number, number, number)
		local need, right, bad = 0, 0, 0
		for r = 1, 5 do
			for c = 1, 5 do
				local want = string.sub(target.rows[r], c, c)
				local have = paint[r][c]
				local wantKey = if want == "a" then target.a elseif want == "b" then (target.b or target.a) else nil
				local haveKey = if have == "." then nil else swatchKeys[tonumber(have) or 0]
				if want ~= "." then
					need += 1
					if haveKey == wantKey then
						right += 1
					elseif haveKey ~= nil then
						bad += 1
					end
				elseif haveKey ~= nil then
					bad += 1
				end
			end
		end
		return need, right, bad
	end

	local function paintCell(r: number, c: number)
		if busy or done >= PAINT_SPRITES then
			return
		end
		local mark = tostring(selected)
		paint[r][c] = if paint[r][c] == mark then "." else mark
		cells[r][c].BackgroundColor3 = if paint[r][c] == "." then UIKit.color("paper") else UIKit.color(swatchKeys[selected])
		Audio.play("pop")
		local need, right, bad = tally()
		if right == need and bad == 0 then
			done += 1
			busy = true
			ctx.pop(cx + math.floor(cw / 2), cy, "Lovely!", UIKit.color("graphics"))
			Audio.play("combo")
			task.delay(0.35, function()
				busy = false
				if done < PAINT_SPRITES and area.Parent then
					nth += 1
					setTarget(TARGETS[order[nth]])
				end
			end)
		end
	end

	for r = 1, 5 do
		paint[r] = {}
		cells[r] = {}
		for c = 1, 5 do
			paint[r][c] = "."
			cells[r][c] = cell(area, string.format("Cell_%d_%d", r, c), UDim2.fromOffset(CELL - 1, CELL - 1), UDim2.fromOffset(cx + (c - 1) * CELL, cy + (r - 1) * CELL), UIKit.color("paper"), function()
				paintCell(r, c)
			end)
		end
	end

	-- the palette, right of the canvas
	local sx = cx + cw + 10
	for i = 1, 3 do
		local b = Instance.new("TextButton")
		b.Name = "Swatch_" .. i
		b.Text = ""
		b.AutoButtonColor = true
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.Size = UDim2.fromOffset(18, 18)
		b.Position = UDim2.fromOffset(sx, cy + (i - 1) * 22)
		b.ZIndex = 8
		local ring = UIKit.rect(b, UDim2.fromOffset(18, 18), nil, UIKit.color("white"), 8)
		ring.Name = "Ring"
		UIKit.rect(b, UDim2.fromOffset(14, 14), UDim2.fromOffset(2, 2), UIKit.color("ink"), 9).Name = "Edge"
		local fill = UIKit.rect(b, UDim2.fromOffset(12, 12), UDim2.fromOffset(3, 3), UIKit.color("blue"), 10)
		fill.Name = "Fill"
		UIKit.text(b, tostring(i), UDim2.fromOffset(10, 10), UDim2.fromOffset(20, 4), { color = UIKit.color("text_dim"), z = 9 })
		b.Activated:Connect(function()
			selected = i
			refreshSwatches()
			Audio.play("click")
		end)
		b.Parent = area
		swatches[i] = b
	end
	setTarget(target)

	return {
		hint = "Pick a colour (1-3), tap to paint",
		update = function(_t: number, _dt: number) end,
		key = function(name: string)
			local n = tonumber(name)
			if n and swatchKeys[n] then
				selected = n
				refreshSwatches()
				Audio.play("click")
			end
		end,
		score = function(): number
			if done >= PAINT_SPRITES then
				return 100
			end
			local need, right, bad = tally()
			local part = if busy then 0 else math.max(0, right - bad) / math.max(1, need)
			return clamp100((done + part) * 100 / PAINT_SPRITES)
		end,
		progress = function(): string
			return string.format("Sprites %d/%d", done, PAINT_SPRITES)
		end,
		done = function(): boolean
			return done >= PAINT_SPRITES
		end,
		auto = function()
			for r = 1, 5 do
				for c = 1, 5 do
					local want = string.sub(target.rows[r], c, c)
					local wantKey = if want == "a" then target.a elseif want == "b" then (target.b or target.a) else nil
					local have = paint[r][c]
					local haveKey = if have == "." then nil else swatchKeys[tonumber(have) or 0]
					if haveKey ~= wantKey then
						if wantKey then
							selected = table.find(swatchKeys, wantKey) or 1
						else
							selected = tonumber(have) or 1
						end
						refreshSwatches()
						paintCell(r, c)
						return
					end
				end
			end
		end,
	}
end

------------------------------------------------------------------ Beat Keeper (Sound)
local TRAVEL = 1.3 -- seconds a note falls
type Window = { d: number, pts: number, text: string, color: string }
local WINDOWS: { Window } = {
	{ d = 0.08, pts = 1, text = "Perfect!", color = "accent" },
	{ d = 0.15, pts = 0.7, text = "Good", color = "good" },
	{ d = 0.22, pts = 0.4, text = "OK", color = "text" },
}
local LATE = 0.22 -- the widest window: a note this late is missed

function Games.beats(ctx: Ctx): Game
	local area, w, h, rng = ctx.area, ctx.w, ctx.h, ctx.rng
	type Note = { t: number, lane: number, judged: boolean, sprite: Frame? }
	local notes: { Note } = {}
	local beat = 0.5
	local tt = 1.6
	local k = 0
	while tt < ctx.seconds - 0.9 do
		if rng:chance(0.7) then
			table.insert(notes, { t = tt, lane = rng:int(1, 2), judged = false })
			if k % 4 == 0 and rng:chance(0.25) then
				table.insert(notes, { t = tt, lane = if notes[#notes].lane == 1 then 2 else 1, judged = false })
			end
		end
		if rng:chance(0.15) then
			table.insert(notes, { t = tt + beat / 2, lane = rng:int(1, 2), judged = false })
		end
		tt += beat
		k += 1
	end
	table.sort(notes, function(a, b)
		return a.t < b.t
	end)
	local LANE_W, PAD_H = 30, 18
	local laneTop, laneH = 0, h - PAD_H - 4
	local hitY = laneTop + laneH - 12
	local laneX = { math.floor(w / 2) - LANE_W - 3, math.floor(w / 2) + 3 }
	local points, combo, best = 0, 0, 0
	local now = 0
	local lastNote = if #notes > 0 then notes[#notes].t else 0
	local flashes: { Frame } = {}

	for lane = 1, 2 do
		local bg = UIKit.rect(area, UDim2.fromOffset(LANE_W, laneH), UDim2.fromOffset(laneX[lane], laneTop), UIKit.color("plate_light"), 7)
		bg.Name = "Lane" .. lane
		bg.BackgroundTransparency = 0.25
		local flash = UIKit.rect(area, UDim2.fromOffset(LANE_W, 4), UDim2.fromOffset(laneX[lane], hitY - 1), UIKit.color("sound"), 8)
		flash.Name = "Flash"
		flash.BackgroundTransparency = 1
		flashes[lane] = flash
	end
	-- the line notes are tapped on
	UIKit.rect(area, UDim2.fromOffset(2 * LANE_W + 10, 2), UDim2.fromOffset(laneX[1] - 2, hitY), UIKit.color("white"), 9).Name = "HitLine"
	local judge = UIKit.text(area, "", UDim2.fromOffset(70, 10), UDim2.fromOffset(laneX[2] + LANE_W + 8, hitY - 5), { color = UIKit.color("text"), z = 9, name = "Judge" })
	local comboText = UIKit.text(area, "", UDim2.fromOffset(70, 10), UDim2.fromOffset(laneX[2] + LANE_W + 8, hitY - 18), { color = UIKit.color("accent"), z = 9, name = "Combo" })

	local function say(text: string, color: Color3)
		UIKit.setText(judge, text)
		UIKit.setTextColor(judge, color)
		UIKit.setText(comboText, if combo >= 3 then string.format("Combo x%d", combo) else "")
	end

	local function hit(lane: number)
		local bestNote: Note? = nil
		local bestD = math.huge
		for _, n in notes do
			if not n.judged and n.lane == lane then
				local d = math.abs(n.t - now)
				if d < bestD then
					bestNote, bestD = n, d
				end
			end
		end
		local flash = flashes[lane]
		flash.BackgroundTransparency = 0.2
		UIKit.tween(flash, 0.2, { BackgroundTransparency = 1 })
		local n = bestNote
		if n and bestD <= LATE then
			n.judged = true
			for _, win in WINDOWS do
				if bestD <= win.d then
					points += win.pts
					combo += 1
					best = math.max(best, combo)
					say(win.text, UIKit.color(win.color))
					break
				end
			end
			local s = n.sprite
			if s then
				s:Destroy()
				n.sprite = nil
			end
			Audio.play("tick", { pitch = if lane == 1 then 1 else 1.25 })
		else
			-- a tap with no note near: a little off the score, so drumming on the pads does not pay
			points = math.max(0, points - 0.25)
			combo = 0
			say("Off beat", UIKit.color("text_dim"))
		end
	end

	-- the pads
	for lane = 1, 2 do
		local b = UIKit.button(area, if lane == 1 then "F" else "J", UDim2.fromOffset(LANE_W, PAD_H), UDim2.fromOffset(laneX[lane], h - PAD_H), function()
			hit(lane)
		end, { name = "Pad_" .. lane, color = UIKit.color("sound"), textColor = UIKit.color("ink") })
		b.ZIndex = 8
	end

	return {
		hint = "F / J or the pads, on the line",
		update = function(t: number, _dt: number)
			now = t
			for _, n in notes do
				if n.judged then
					continue
				end
				local dt = n.t - t
				if dt < -LATE then
					n.judged = true
					combo = 0
					say("Miss", UIKit.color("bad"))
					local s = n.sprite
					if s then
						s:Destroy()
						n.sprite = nil
					end
				elseif dt <= TRAVEL then
					local y = hitY - math.floor(dt / TRAVEL * (hitY - laneTop - 6) + 0.5) - 6
					local sp: Frame = n.sprite or PixelSprites.sprite(area, PixelSprites.NOTE, nil, 2, 9)
					n.sprite = sp
					sp.Position = UDim2.fromOffset(laneX[n.lane] + math.floor((LANE_W - 12) / 2), y)
				end
			end
		end,
		key = function(name: string)
			if name == "lane1" or name == "left" then
				hit(1)
			elseif name == "lane2" or name == "right" then
				hit(2)
			end
		end,
		score = function(): number
			return clamp100(points * 100 / math.max(1, #notes))
		end,
		progress = function(): string
			return string.format("Best combo %d", best)
		end,
		done = function(): boolean
			return now > lastNote + 0.5
		end,
		auto = function()
			for _, n in notes do
				if not n.judged and math.abs(n.t - now) <= 0.05 then
					hit(n.lane)
					return
				end
			end
		end,
	}
end

------------------------------------------------------------------ Bug Squash (bugs)
local SQUASH_TARGET = 15 -- bugs for a score of 100

function Games.bugs(ctx: Ctx): Game
	local area, w, h, rng = ctx.area, ctx.w, ctx.h, ctx.rng
	local MW, MH, GX, GY = 30, 24, 6, 4
	local gw, gh = 4 * (MW + GX) - GX, 3 * (MH + GY) - GY
	local x0, y0 = math.floor((w - gw) / 2), math.max(0, math.floor((h - gh) / 2))
	type Hole = { button: TextButton, screen: Frame, bug: Frame, splat: Frame, untilT: number }
	local holes: { Hole } = {}
	local squashed, missed, escaped = 0, 0, 0
	local nextSpawn = 0.6
	local now = 0

	local function squash(i: number)
		local hole = holes[i]
		if hole.untilT > now then
			hole.untilT = 0
			hole.bug.Visible = false
			hole.splat.Visible = true
			squashed += 1
			Audio.play("squish")
			ctx.pop(hole.button.Position.X.Offset + MW / 2, hole.button.Position.Y.Offset, "+1", UIKit.color("good"))
			task.delay(0.3, function()
				if hole.splat.Parent then
					hole.splat.Visible = false
				end
			end)
		else
			missed += 1
			hole.screen.BackgroundColor3 = UIKit.color("bad")
			task.delay(0.12, function()
				if hole.screen.Parent then
					hole.screen.BackgroundColor3 = UIKit.color("screen_off")
				end
			end)
		end
	end

	for i = 1, 12 do
		local col, row = (i - 1) % 4, (i - 1) // 4
		local b = Instance.new("TextButton")
		b.Name = "Hole_" .. i
		b.Text = ""
		b.AutoButtonColor = true
		b.BackgroundTransparency = 1
		b.BorderSizePixel = 0
		b.Size = UDim2.fromOffset(MW, MH)
		b.Position = UDim2.fromOffset(x0 + col * (MW + GX), y0 + row * (MH + GY))
		b.ZIndex = 8
		-- a little monitor: the case, the screen, the stand
		UIKit.plate(b, UDim2.fromOffset(MW, MH - 4), nil, UIKit.color("steel_dark"), 0, 1).ZIndex = 8
		local screen = UIKit.rect(b, UDim2.fromOffset(MW - 4, MH - 8), UDim2.fromOffset(2, 2), UIKit.color("screen_off"), 9)
		screen.Name = "Screen"
		UIKit.rect(b, UDim2.fromOffset(8, 4), UDim2.fromOffset(math.floor(MW / 2) - 4, MH - 4), UIKit.color("steel"), 8)
		local bug = PixelSprites.sprite(b, PixelSprites.BUG, UDim2.fromOffset(math.floor((MW - 16) / 2), 2), 2, 10)
		bug.Name = "Bug"
		bug.Visible = false
		local splat = PixelSprites.sprite(b, PixelSprites.SPLAT, UDim2.fromOffset(math.floor((MW - 16) / 2), 2), 2, 10)
		splat.Name = "Splat"
		splat.Visible = false
		b.Activated:Connect(function()
			squash(i)
		end)
		b.Parent = area
		holes[i] = { button = b, screen = screen, bug = bug, splat = splat, untilT = 0 }
	end

	return {
		hint = "Tap the bugs before they hide",
		update = function(t: number, _dt: number)
			now = t
			local share = math.clamp(t / ctx.seconds, 0, 1)
			for _, hole in holes do
				if hole.bug.Visible and hole.untilT <= t then
					hole.bug.Visible = false
					if hole.untilT > 0 then
						escaped += 1
					end
					hole.untilT = 0
				end
			end
			if t >= nextSpawn and t < ctx.seconds - 0.4 then
				nextSpawn = t + 0.62 - 0.22 * share
				local free = {}
				for i, hole in holes do
					if not hole.bug.Visible and not hole.splat.Visible then
						table.insert(free, i)
					end
				end
				if #free > 0 then
					local hole = holes[free[rng:int(1, #free)]]
					hole.untilT = t + 1.05 - 0.35 * share
					hole.bug.Visible = true
					Audio.play("pop", { volume = 0.5, pitch = 1.3 })
				end
			end
		end,
		key = function(_name: string) end,
		score = function(): number
			return clamp100(squashed * 100 / SQUASH_TARGET - missed * 2)
		end,
		progress = function(): string
			return string.format("Squashed %d", squashed)
		end,
		done = function(): boolean
			return false
		end,
		auto = function()
			for i, hole in holes do
				if hole.untilT > now then
					squash(i)
					return
				end
			end
		end,
	}
end

return Games
