--!strict
-- The minigames' cards (GAME_DESIGN 14; docs/ARCHITECTURE.md 10.8): the push picker (the four score games), the play
-- card (the game's name, its score, the clock bar, the play area from UI/MinigameGames and the controls), and the
-- results (the grade letter dropping in with a burst of sparkles, the score and what it did to the game). The server
-- starts a game (mini.start: the push is spent, the clock held) and applies its finish (mini.finish with the start's
-- token); the client only plays it. While a game runs its keys are bound above the founder's walking keys, so the
-- arrows and WASD steer the game, not the founder.
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local Types = require(ReplicatedStorage.Shared.Types)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Dev = require(ReplicatedStorage.Shared.Logic.Dev)
local Minigames = require(ReplicatedStorage.Shared.Logic.Minigames)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Games = require(script.Parent.MinigameGames)

local MinigameUI = {}

-- A minigame's result came back (the server's Minigames.finish data): the HUD cheers the crew.
MinigameUI.Finished = Util.Signal() :: Types.Signal<{ [string]: any }>

local COUNTDOWN = { "3", "2", "1", "Go!" }
local COUNT_STEP = 0.4
local ACTION = "BSS_Minigame"

local KEYMAP: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Up] = "up",
	[Enum.KeyCode.W] = "up",
	[Enum.KeyCode.Down] = "down",
	[Enum.KeyCode.S] = "down",
	[Enum.KeyCode.Left] = "left",
	[Enum.KeyCode.A] = "left",
	[Enum.KeyCode.Right] = "right",
	[Enum.KeyCode.D] = "right",
	[Enum.KeyCode.F] = "lane1",
	[Enum.KeyCode.Z] = "lane1",
	[Enum.KeyCode.J] = "lane2",
	[Enum.KeyCode.X] = "lane2",
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
}

local GRADE_COLOR: { [string]: string } = { S = "accent", A = "good", B = "button", C = "text_dim" }
local GRADE_WORDS: { [string]: string } = { S = "Superb!", A = "Great work!", B = "Not bad!", C = "Keep at it!" }
local GRADE_SOUND: { [string]: string } = { S = "rare_fanfare", A = "fanfare", B = "reward", C = "ding" }

local current: TextButton? = nil
local holding = false
local playing: Games.Game? = nil -- the game in play (MinigameUI.debugAuto)
local playingKind: string? = nil

local function hold(on: boolean)
	if holding ~= on then
		holding = on
		StateClient.signal("pause", { key = "pick", on = on })
	end
end

local function close()
	local f = current
	current = nil
	if f then
		f:Destroy()
	end
	hold(false)
end

-- A card in the middle of the Popup root with a dim shade behind it; it rises into place.
local function card(w: number, h: number, name: string): (TextButton, Frame)
	close()
	local canvas = UIKit.canvas("Popup")
	local s = UIKit.size("Popup")
	local shade = Instance.new("TextButton")
	shade.Name = name
	shade.Text = ""
	shade.AutoButtonColor = false
	shade.BackgroundColor3 = UIKit.color("ink")
	shade.BackgroundTransparency = 1
	shade.BorderSizePixel = 0
	shade.Size = UDim2.fromScale(1, 1)
	shade.ZIndex = 5
	local cw, ch = math.min(w, s.X - 8), math.min(h, s.Y - 6)
	local x, y = math.floor((s.X - cw) / 2), math.floor((s.Y - ch) / 2)
	local f = UIKit.plate(shade, UDim2.fromOffset(cw, ch), UDim2.fromOffset(x, y + 10), UIKit.color("plate"), 0, 3)
	f.Name = "Frame"
	f.ZIndex = 6
	shade.Parent = canvas
	current = shade :: any
	UIKit.tween(shade, 0.15, { BackgroundTransparency = 0.4 })
	UIKit.tween(f, 0.15, { Position = UDim2.fromOffset(x, y) })
	Audio.play("open")
	return shade, f
end

function MinigameUI.isOpen(): boolean
	return current ~= nil
end

------------------------------------------------------------------ the push picker
-- The four score games for a banked push (the HUD's Push! button).
function MinigameUI.picker()
	local v = StateClient.view()
	local proj = if v then v.project else nil
	if proj == nil then
		return
	end
	local _, f = card(236, 116, "MiniPicker")
	hold(true)
	local w = f.Size.X.Offset
	UIKit.text(f, "Push the game!", UDim2.new(1, -10, 0, 18), UDim2.fromOffset(5, 2), { face = "big", color = UIKit.color("accent"), kind = "title", z = 7 })
	UIKit.text(f, string.format("%d push%s banked. Pick a minigame:", proj.pushes, if proj.pushes == 1 then "" else "es"), UDim2.new(1, -10, 0, 10), UDim2.fromOffset(5, 20), { color = UIKit.color("text_dim"), z = 7, name = "Banked" })
	local bw = math.floor((w - 15) / 2)
	for i, kind in Minigames.PUSH_ORDER do
		local def = Minigames.KINDS[kind]
		local axis = def.axis :: Types.Axis
		local col, row = (i - 1) % 2, (i - 1) // 2
		local b = UIKit.button(f, def.name, UDim2.fromOffset(bw, 28), UDim2.fromOffset(5 + col * (bw + 5), 33 + row * 32), function()
			MinigameUI.play(kind)
		end, { name = "Mini_" .. kind, color = UIKit.color("plate_light") })
		b.ZIndex = 7
		local words = b:FindFirstChild("Words")
		if words and words:IsA("TextLabel") then
			words.Size = UDim2.new(1, -4, 0, 10)
			words.Position = UDim2.fromOffset(2, 3)
		end
		UIKit.text(b, "+" .. Dev.AXIS_NAMES[axis], UDim2.new(1, -4, 0, 10), UDim2.fromOffset(2, 15), { x = "center", color = UIKit.color(axis), z = 3 })
		UIKit.rect(b, UDim2.fromOffset(3, 20), UDim2.fromOffset(3, 4), UIKit.color(axis), 3)
	end
	local later = UIKit.button(f, "Later", UDim2.fromOffset(UIKit.buttonWidth("Later", 5), 12), UDim2.new(1, -UIKit.buttonWidth("Later", 5) - 5, 1, -15), function()
		Audio.play("close")
		close()
	end, { name = "Later", color = UIKit.color("plate_light") })
	later.ZIndex = 7
end

------------------------------------------------------------------ playing
local function errText(err: string?): string
	if err == "cooldown" then
		return "Not yet: nothing to play right now."
	elseif err == "not_built" then
		return "Bug Squash is for polishing a game with bugs."
	elseif err == "busy" then
		return "A minigame is already running."
	elseif err == "no_project" then
		return "Start a game first."
	end
	return "That didn't work. Try again."
end

local function bindKeys(fn: (string) -> ()): () -> ()
	local keys: { Enum.KeyCode } = {}
	for k in KEYMAP do
		table.insert(keys, k)
	end
	local ok = pcall(function()
		ContextActionService:BindActionAtPriority(ACTION, function(_name: string, state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
			if state == Enum.UserInputState.Begin then
				local m = KEYMAP[input.KeyCode]
				if m then
					fn(m)
				end
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.ContextActionPriority.High.Value + 10, table.unpack(keys))
	end)
	if ok then
		return function()
			pcall(function()
				ContextActionService:UnbindAction(ACTION)
			end)
		end
	end
	local conn = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed then
			local m = KEYMAP[input.KeyCode]
			if m then
				fn(m)
			end
		end
	end)
	return function()
		conn:Disconnect()
	end
end

-- The results: the grade letter drops in (ink outline, a little bounce) and sparkles burst from it.
local function showResults(f: Frame, area: Frame, data: { [string]: any })
	UIKit.clear(area)
	local aw, ah = area.Size.X.Offset, area.Size.Y.Offset
	local grade = tostring(data.grade or "C")
	local gcol = UIKit.color(GRADE_COLOR[grade] or "text")
	local rows = PixelSprites.glyphRows(grade)
	local gw, gh = PixelSprites.size(rows)
	local SC = if ah >= 100 then 6 else 5
	-- a badge: the letter on a plate, outlined in ink with a drop shadow
	local bw, bh = gw * SC + 16, gh * SC + 16
	local letter = UIKit.plate(nil, UDim2.fromOffset(bw, bh), nil, UIKit.color("plate_light"), 0, 3)
	letter.Name = "Grade"
	letter.ZIndex = 8
	local ox, oy = 8, 7
	PixelSprites.draw(letter, rows, { ["#"] = "ink" }, UDim2.fromOffset(ox + 2, oy + 3), SC, 9)
	for _, d in { { -2, 0 }, { 2, 0 }, { 0, -2 }, { 0, 2 } } do
		PixelSprites.draw(letter, rows, { ["#"] = "ink" }, UDim2.fromOffset(ox + d[1], oy + d[2]), SC, 9)
	end
	local face = PixelSprites.draw(letter, rows, { ["#"] = "white" }, UDim2.fromOffset(ox, oy), SC, 10)
	PixelSprites.tint(face, gcol)
	local lx = math.max(4, math.floor(aw / 2) - bw - 30)
	local ly = math.max(0, math.floor((ah - bh) / 2) - 4)
	letter.Position = UDim2.fromOffset(lx, ly - 30)
	letter.Parent = area
	local tx = lx + bw + 14
	local tw = aw - tx - 4
	UIKit.text(area, GRADE_WORDS[grade] or "", UDim2.fromOffset(tw, 18), UDim2.fromOffset(tx, ly), { face = "big", color = gcol, kind = "title", z = 8, name = "Words" })
	UIKit.text(area, string.format("Score %d/100", data.score or 0), UDim2.fromOffset(tw, 10), UDim2.fromOffset(tx, ly + 20), { color = UIKit.color("text"), z = 8, name = "Score" })
	local reward: string
	local rcol: Color3
	if data.axis then
		reward = string.format("+%d %s", data.points or 0, Dev.AXIS_NAMES[data.axis] or "")
		rcol = UIKit.color(data.axis)
	else
		local n = data.removed or 0
		reward = if n == 1 then "1 bug squashed!" else string.format("%d bugs squashed!", n)
		rcol = UIKit.color("good")
	end
	local rl = UIKit.text(area, reward, UDim2.fromOffset(tw, 10), UDim2.fromOffset(tx, ly + 32), { color = rcol, z = 8, name = "Reward" })
	rl.Visible = false

	-- the drop (a back-out ease), then the burst and the reward
	local t0 = os.clock()
	local sparks: { { f: Frame, x: number, y: number, vx: number, vy: number } } = {}
	local burst = false
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if letter.Parent == nil then
			if conn then
				conn:Disconnect()
			end
			return
		end
		local p = math.clamp(t / 0.35, 0, 1)
		local c1 = 1.70158
		local e = 1 + (c1 + 1) * (p - 1) ^ 3 + c1 * (p - 1) ^ 2
		letter.Position = UDim2.fromOffset(lx, ly - 30 + math.floor(30 * e + 0.5))
		if p >= 1 and not burst then
			burst = true
			rl.Visible = true
			Audio.play(GRADE_SOUND[grade] or "ding")
			local cx, cy = lx + math.floor(bw / 2), ly + math.floor(bh / 2)
			local n = if grade == "S" then 22 elseif grade == "A" then 16 elseif grade == "B" then 10 else 4
			for i = 1, n do
				local a = (i / n) * math.pi * 2 + math.random() * 0.4
				local sp = 50 + math.random() * 50
				local keyc = if i % 3 == 0 then "white" elseif i % 3 == 1 then (GRADE_COLOR[grade] or "accent") else (if data.axis then data.axis else "good")
				local r = UIKit.rect(area, UDim2.fromOffset(2, 2), UDim2.fromOffset(cx, cy), UIKit.color(keyc), 10)
				r.Name = "Spark"
				table.insert(sparks, { f = r, x = cx, y = cy, vx = math.cos(a) * sp, vy = math.sin(a) * sp - 30 })
			end
		end
		if burst then
			local dt = 1 / 60
			for _, s in sparks do
				s.vy += 120 * dt
				s.x += s.vx * dt
				s.y += s.vy * dt
				s.f.Position = UDim2.fromOffset(math.floor(s.x), math.floor(s.y))
				s.f.BackgroundTransparency = math.clamp((t - 0.6) / 0.6, 0, 1)
			end
			if t > 1.3 then
				for _, s in sparks do
					s.f:Destroy()
				end
				table.clear(sparks)
				if conn then
					conn:Disconnect()
				end
			end
		end
	end)

	local nice = UIKit.button(f, "Nice!", UDim2.fromOffset(44, 13), UDim2.new(1, -49, 1, -16), function()
		Audio.play("close")
		close()
		MinigameUI.Finished:Fire(data)
	end, { color = UIKit.color("button_ok"), name = "Nice" })
	nice.ZIndex = 8
end

-- Play `kind`: ask the server to start it, count in, run it for its seconds, send the score, show the results.
function MinigameUI.play(kind: string)
	local def = Minigames.KINDS[kind]
	if def == nil or current and current.Name == "MiniPlay" then
		return
	end
	local asked = os.clock()
	local res = StateClient.request("mini.start", { kind = kind })
	if not res.ok or type(res.data) ~= "table" then
		close()
		Audio.play("deny")
		UIKit.notice(errText(res.err), UIKit.color("bad"))
		return
	end
	local data = res.data :: { [string]: any }
	local token = tonumber(data.token) or 0
	local seconds = tonumber(data.seconds) or Tuning.MiniSeconds
	local rng = Util.newRng(tonumber(data.seed) or 1)

	local _, f = card(268, 178, "MiniPlay")
	hold(true)
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	local axisCol = if def.axis then UIKit.color(def.axis) else UIKit.color("good")
	UIKit.text(f, def.name, UDim2.fromOffset(w - 80, 10), UDim2.fromOffset(6, 3), { color = UIKit.color("accent"), z = 7, name = "Title" })
	UIKit.text(f, if def.axis then "+" .. Dev.AXIS_NAMES[def.axis] .. ": " .. def.blurb else def.blurb, UDim2.fromOffset(w - 80, 10), UDim2.fromOffset(6, 12), { color = axisCol, z = 7 })
	local scoreLabel = UIKit.text(f, "0", UDim2.fromOffset(60, 18), UDim2.new(1, -66, 0, 2), { face = "big", x = "right", color = UIKit.color("text"), z = 7, name = "Score" })
	local _, setClock = UIKit.bar(f, UDim2.new(1, -12, 0, 4), UDim2.fromOffset(6, 23), UIKit.color("accent"), UIKit.color("plate_light"))
	setClock(1)
	local clockFill = (f:FindFirstChild("Bar") :: Frame):FindFirstChild("Fill") :: Frame
	local area = Instance.new("Frame")
	area.Name = "Area"
	area.BackgroundTransparency = 1
	area.Size = UDim2.fromOffset(w - 12, h - 44)
	area.Position = UDim2.fromOffset(6, 30)
	area.ZIndex = 7
	area.ClipsDescendants = true
	area.Parent = f
	local hint = UIKit.text(f, "", UDim2.fromOffset(w - 90, 10), UDim2.new(0, 6, 1, -12), { color = UIKit.color("text_dim"), z = 7, name = "Hint" })
	local tally = UIKit.text(f, "", UDim2.fromOffset(80, 10), UDim2.new(1, -86, 1, -12), { x = "right", color = UIKit.color("text"), z = 7, name = "Tally" })

	-- floating words and the card's shake
	type Pop = { l: TextLabel, x: number, y: number, t0: number }
	local pops: { Pop } = {}
	local shakeUntil = 0
	local base = f.Position
	local ctx: Games.Ctx = {
		area = area,
		w = area.Size.X.Offset,
		h = area.Size.Y.Offset,
		rng = rng,
		seconds = seconds,
		pop = function(x: number, y: number, text: string, color: Color3)
			local tw = UIKit.textWidth(text) + 4
			local l = UIKit.text(area, text, UDim2.fromOffset(tw, 10), UDim2.fromOffset(x - math.floor(tw / 2), y), { x = "center", color = color, kind = "outline", z = 12, name = "Pop" })
			table.insert(pops, { l = l, x = x - math.floor(tw / 2), y = y, t0 = os.clock() })
		end,
		shake = function()
			shakeUntil = os.clock() + 0.2
		end,
	}
	local mg: Games.Game
	if kind == "code" then
		mg = Games.code(ctx)
	elseif kind == "ideas" then
		mg = Games.ideas(ctx)
	elseif kind == "pixels" then
		mg = Games.pixels(ctx)
	elseif kind == "beats" then
		mg = Games.beats(ctx)
	else
		mg = Games.bugs(ctx)
	end
	UIKit.setText(hint, mg.hint)
	playing, playingKind = mg, kind

	-- the count-in over the area
	local count = UIKit.text(f, "", UDim2.new(1, 0, 0, 18), UDim2.new(0, 0, 0.5, -6), { x = "center", face = "big", kind = "title", color = UIKit.color("accent"), z = 14, name = "Count" })
	local veil = UIKit.rect(area, UDim2.fromScale(1, 1), nil, UIKit.color("ink"), 13)
	veil.Name = "Veil"
	veil.BackgroundTransparency = 0.35
	veil.Active = true
	for _, word in COUNTDOWN do
		UIKit.setText(count, word)
		Audio.play(if word == "Go!" then "ding" else "tick")
		task.wait(COUNT_STEP)
		if f.Parent == nil then
			return
		end
	end
	count:Destroy()
	veil:Destroy()
	base = f.Position

	local t0 = os.clock()
	local last = t0
	local finished = false
	local unbind = bindKeys(function(name: string)
		if not finished then
			mg.key(name)
		end
	end)
	local conn: RBXScriptConnection? = nil
	local function finish()
		if finished then
			return
		end
		finished = true
		playing, playingKind = nil, nil
		if conn then
			conn:Disconnect()
		end
		unbind()
		local score = mg.score()
		task.spawn(function()
			-- the server refuses a finish sooner than Tuning.MiniMinSec after the start
			local wait = Tuning.MiniMinSec + 0.3 - (os.clock() - asked)
			if wait > 0 then
				task.wait(wait)
			end
			Audio.play("drumroll")
			local fin = StateClient.request("mini.finish", { token = token, score = score })
			if f.Parent == nil then
				return
			end
			for _, p in pops do
				p.l:Destroy()
			end
			table.clear(pops)
			UIKit.setText(hint, "")
			UIKit.setText(tally, "")
			if fin.ok and type(fin.data) == "table" then
				scoreLabel.Visible = false
				local bar = f:FindFirstChild("Bar")
				if bar and bar:IsA("GuiObject") then
					bar.Visible = false
				end
				showResults(f, area, fin.data :: { [string]: any })
			else
				UIKit.notice(errText(fin.err), UIKit.color("bad"))
				close()
			end
		end)
	end
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		local t = now - t0
		local dt = now - last
		last = now
		if f.Parent == nil then
			finished = true
			playing, playingKind = nil, nil
			unbind()
			if conn then
				conn:Disconnect()
			end
			return
		end
		local ok, err = pcall(function()
			mg.update(t, dt)
		end)
		if not ok then
			warn("[MinigameUI] " .. kind .. ": " .. tostring(err))
		end
		local left = math.max(0, seconds - t)
		setClock(left / seconds)
		if clockFill then
			clockFill.BackgroundColor3 = if left < 4 then UIKit.color("bad") else UIKit.color("accent")
		end
		UIKit.setText(scoreLabel, tostring(mg.score()))
		UIKit.setText(tally, mg.progress())
		for i = #pops, 1, -1 do
			local p = pops[i]
			local pt = now - p.t0
			if pt > 0.7 or p.l.Parent == nil then
				p.l:Destroy()
				table.remove(pops, i)
			else
				p.l.Position = UDim2.fromOffset(p.x, p.y - math.floor(pt * 18))
			end
		end
		if now < shakeUntil then
			local k = if math.floor(now * 40) % 2 == 0 then 2 else -2
			f.Position = UDim2.new(base.X.Scale, base.X.Offset + k, base.Y.Scale, base.Y.Offset)
		elseif f.Position ~= base then
			f.Position = base
		end
		if t >= seconds or mg.done() then
			finish()
		end
	end)
end

-- The kind of the game in play, or nil (the sims and the previews).
function MinigameUI.playing(): string?
	return playingKind
end

-- One right move in the game in play (the sims' and the previews' player).
function MinigameUI.debugAuto()
	local g = playing
	if g then
		g.auto()
	end
end

return MinigameUI
