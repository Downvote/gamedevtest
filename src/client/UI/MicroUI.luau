--!strict
-- Making a game (GAME_DESIGN 5, 6; docs/ARCHITECTURE.md 10.8): the card with the game's three ideas, each one's
-- microgame (Play, Retry at any time, or Play all for the ones not played yet), the sales boost so far, and Launch!
-- once all three have been played. A microgame: the server starts it (micro.start: a token, a seed, the difficulty),
-- it plays full screen in 3D: the idea's stage (UI/MicroStage, a diorama room the pixel filter draws like the office)
-- with the player's own founder in it, the HUD hidden. A curtain with the idea's icon and order word covers the
-- screen while the stage's picture is baked (MicroIntro at least), then the engine (UI/MicroGames) runs while a rope
-- fuse burns down to its bomb along the bottom (shorter with the difficulty); the idea's modifier changes how it
-- plays (Turbo faster on a shorter fuse, Tiny small targets, Shaky the screen shakes, Glitched it blinks out, Haunted
-- only a roving spotlight shows it, Cosmic all but the dark). A WIN or LOSE stamp while the founder cheers or
-- stumbles, then micro.finish with the result, and back to the card over the street. The runner also draws the
-- engines' effects over the stage: floating words, bursts of 1 px bits, floating sprites and flashes. The launch card
-- shows the income it earns for good. While a microgame runs its keys are bound above the founder's walking keys.
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Types = require(ReplicatedStorage.Shared.Types)
local Tuning = require(ReplicatedStorage.Shared.Config.Tuning)
local IdeasData = require(ReplicatedStorage.Shared.Data.Ideas)
local Modifiers = require(ReplicatedStorage.Shared.Data.Modifiers)
local Util = require(ReplicatedStorage.Shared.Logic.Util)
local Ideas = require(ReplicatedStorage.Shared.Logic.Ideas)
local Numbers = require(ReplicatedStorage.Shared.Logic.Numbers)
local StateClient = require(script.Parent.Parent.Controllers.StateClient)
local Audio = require(script.Parent.Parent.Controllers.Audio)
local UIKit = require(script.Parent.UIKit)
local PixelSprites = require(script.Parent.PixelSprites)
local Games = require(script.Parent.MicroGames)
local MicroStage = require(script.Parent.MicroStage)
local PixelRenderer = require(script.Parent.Parent.Pixel.PixelRenderer)
local Words = require(script.Parent.Words)

local MicroUI = {}

-- A game was launched (the server's Game record): the HUD cheers.
MicroUI.Launched = Util.Signal() :: Types.Signal<Types.Game>

local ACTION = "BSS_Micro"
local KEYMAP: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Up] = "up",
	[Enum.KeyCode.W] = "up",
	[Enum.KeyCode.Down] = "down",
	[Enum.KeyCode.S] = "down",
	[Enum.KeyCode.Left] = "left",
	[Enum.KeyCode.A] = "left",
	[Enum.KeyCode.Right] = "right",
	[Enum.KeyCode.D] = "right",
	[Enum.KeyCode.Space] = "go",
	[Enum.KeyCode.Return] = "go",
	[Enum.KeyCode.F] = "go",
	[Enum.KeyCode.J] = "go",
	[Enum.KeyCode.One] = "1",
	[Enum.KeyCode.Two] = "2",
	[Enum.KeyCode.Three] = "3",
	[Enum.KeyCode.Four] = "4",
	[Enum.KeyCode.Five] = "5",
	[Enum.KeyCode.Six] = "6",
}

local shade: TextButton? = nil
local frame: Frame? = nil
local mode: string? = nil -- "card" | "play" | "launch"
local playing: Games.Micro? = nil
local playingKind: string? = nil
local pendingOpen = 0 -- os.clock until which the card opens as soon as the view has the project (just made)
local lastCtx: { [string]: any }? = nil -- the microgame in play's settings (MicroUI.debugCtx)
local live = false -- the microgame in play has started (its curtain lifted): keys, pads and debugAuto act

local endPlay: () -> ()

local function close()
	if endPlay then
		endPlay()
	end
	local s = shade
	shade, frame, mode, playing, playingKind = nil, nil, nil, nil, nil
	if s then
		s:Destroy()
	end
end

-- The card's frame (made once while open; its content is cleared and rebuilt for each screen).
local fresh = false -- the card was just opened: its rows slide in
local function ensureFrame(): Frame
	if frame and shade and shade.Parent then
		return frame :: Frame
	end
	local canvas = UIKit.canvas("Popup")
	local s = UIKit.size("Popup")
	local sh = Instance.new("TextButton")
	sh.Name = "MicroCard"
	sh.Text = ""
	sh.AutoButtonColor = false
	sh.BackgroundColor3 = UIKit.color("ink")
	sh.BackgroundTransparency = 1
	sh.BorderSizePixel = 0
	sh.Size = UDim2.fromScale(1, 1)
	sh.ZIndex = 5
	local w, h = math.min(280, s.X - 8), math.min(178, s.Y - 6)
	local x, y = math.floor((s.X - w) / 2), math.floor((s.Y - h) / 2)
	local f = UIKit.plate(sh, UDim2.fromOffset(w, h), UDim2.fromOffset(x, y + 10), UIKit.color("plate"), 0, 3)
	f.Name = "Frame"
	f.ZIndex = 6
	sh.Parent = canvas
	UIKit.tween(sh, 0.15, { BackgroundTransparency = 0.4 })
	UIKit.tween(f, 0.15, { Position = UDim2.fromOffset(x, y) })
	Audio.play("open")
	shade, frame = sh, f
	fresh = true
	return f
end

local shownWon: { [string]: { number } } = {} -- the results the card last showed, by game title (a new one stamps in)

local function clearFrame(f: Frame)
	for _, c in f:GetChildren() do
		if c.Name ~= "Fill" then
			c:Destroy()
		end
	end
end

function MicroUI.isOpen(): boolean
	return shade ~= nil
end

------------------------------------------------------------------ the card
local function modTag(c: Types.Card): string
	local m = Modifiers.byId[c.mod]
	return if m and m.id ~= "plain" then m.name else ""
end

local showCard: () -> ()

local function nextUnplayed(proj: Types.Making, after: number): number?
	for i = after + 1, 3 do
		if proj.won[i] < 0 then
			return i
		end
	end
	return nil
end

local playSlot: (slot: number, chain: boolean) -> ()

showCard = function()
	local v = StateClient.view()
	local proj = if v then v.project else nil
	if proj == nil then
		close()
		return
	end
	local p = proj :: Types.Making
	local f = ensureFrame()
	clearFrame(f)
	mode = "card"
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	UIKit.text(f, "Making", UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 3), { color = UIKit.color("text_dim"), z = 7 })
	UIKit.text(f, p.title, UDim2.fromOffset(w - 12, 18), UDim2.fromOffset(6, 11), { face = "big", kind = "title", color = UIKit.color("accent"), z = 7, name = "GameTitle" })
	local rowH = math.min(32, math.floor((h - 66) / 3))
	local played, wins = true, 0
	local slideIn = fresh
	fresh = false
	local before = shownWon[p.title]
	shownWon[p.title] = table.clone(p.won)
	for i, c in p.ideas do
		local y = 31 + (i - 1) * (rowH + 2)
		local def = IdeasData.byId[c.id]
		local r = UIKit.plate(f, UDim2.fromOffset(w - 12, rowH), UDim2.fromOffset(6, y), UIKit.color("plate_light"), 0, 2)
		r.Name = "Slot_" .. i
		r.ZIndex = 7
		if slideIn then
			-- the rows slide in one after another
			r.Position = UDim2.fromOffset(6 + 40 + i * 12, y)
			task.delay((i - 1) * 0.05, function()
				if r.Parent then
					UIKit.tween(r, 0.16, { Position = UDim2.fromOffset(6, y) })
					Audio.play("flip", { volume = 0.6, pitch = 0.95 + i * 0.05 })
				end
			end)
		end
		PixelSprites.image(r, "icon_" .. c.id, UDim2.fromOffset(4, math.floor((rowH - 16) / 2)), 8)
		local tier = Ideas.tier(c)
		UIKit.text(r, Ideas.name(c), UDim2.fromOffset(w - 110, 10), UDim2.fromOffset(24, 2), { color = UIKit.color(Ideas.tierColor(tier)), z = 8 })
		local mod = Modifiers.byId[c.mod]
		local sub = string.format('"%s"  %sDifficulty %d', if def then def.word else "", if mod and mod.id ~= "plain" then mod.name .. "  " else "", Ideas.difficulty(c))
		UIKit.text(r, sub, UDim2.fromOffset(w - 110, 10), UDim2.fromOffset(24, rowH - 12), { color = UIKit.color("text_dim"), z = 8 })
		local won = p.won[i]
		played = played and won >= 0
		if won == 1 then
			wins += 1
		end
		local result = UIKit.text(r, if won == 1 then "WIN" elseif won == 0 then "LOSE" else "", UDim2.fromOffset(34, 10), UDim2.new(1, -86, 0, math.floor(rowH / 2) - 5), { x = "right", color = if won == 1 then UIKit.color("good") else UIKit.color("bad"), z = 8, name = "Result" })
		if before and before[i] ~= won and won >= 0 then
			-- a new result stamps in from above with a burst
			local at = result.Position
			result.Position = UDim2.new(at.X.Scale, at.X.Offset, at.Y.Scale, at.Y.Offset - 10)
			UIKit.tween(result, 0.14, { Position = at })
			task.delay(0.14, function()
				if r.Parent then
					UIKit.burst(r, r.Size.X.Offset - 70, math.floor(rowH / 2), if won == 1 then { "good", "white", "accent" } else { "bad", "white" }, if won == 1 then 14 else 6)
					Audio.play(if won == 1 then "ding" else "pop")
				end
			end)
		end
		local b = UIKit.button(r, if won < 0 then "Play" else "Retry", UDim2.fromOffset(44, 14), UDim2.new(1, -48, 0, math.floor((rowH - 14) / 2)), function()
			playSlot(i, false)
		end, { name = (if won < 0 then "Play_" else "Retry_") .. i, color = if won < 0 then UIKit.color("accent") else UIKit.color("plate"), textColor = if won < 0 then UIKit.color("ink") else nil })
		b.ZIndex = 8
	end
	UIKit.text(f, string.format("Sales x%.2f  (each win +%d%%)", 1 + Tuning.WinBoost * wins, math.floor(Tuning.WinBoost * 100 + 0.5)), UDim2.fromOffset(w - 12, 10), UDim2.new(0, 6, 1, -30), { color = UIKit.color("good"), z = 7, name = "Boost" })
	local bw = math.floor((w - 18) / 3)
	local first = nextUnplayed(p, 0)
	local pa = UIKit.button(f, "Play all", UDim2.fromOffset(bw, 14), UDim2.new(0, 6, 1, -18), function()
		local n = nextUnplayed(p, 0)
		if n then
			playSlot(n, true)
		end
	end, { name = "PlayAll", color = UIKit.color("accent"), textColor = UIKit.color("ink"), enabled = first ~= nil })
	pa.ZIndex = 7
	local la = UIKit.button(f, "Launch!", UDim2.fromOffset(bw, 14), UDim2.new(0, 9 + bw, 1, -18), function()
		local res = StateClient.request("game.launch", {})
		if res.ok and type(res.data) == "table" then
			MicroUI.showLaunch(res.data :: Types.Game)
		else
			Audio.play("deny")
			UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
		end
	end, { name = "Launch", color = UIKit.color("button_ok"), enabled = played })
	la.ZIndex = 7
	if played then
		-- the Launch button gleams while it is the thing to do
		task.spawn(function()
			while la.Parent and mode == "card" do
				UIKit.shine(la)
				task.wait(1.8)
			end
		end)
	end
	local cl = UIKit.button(f, "Later", UDim2.fromOffset(bw, 14), UDim2.new(0, 12 + 2 * bw, 1, -18), function()
		Audio.play("close")
		close()
	end, { name = "CloseMicro", color = UIKit.color("plate_light") })
	cl.ZIndex = 7
end

------------------------------------------------------------------ a microgame
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

local function has(list: { string }, x: string): boolean
	return table.find(list, x) ~= nil
end

-- The play overlay: a microgame's stage (UI/MicroStage, drawn full screen by the pixel filter) and its frame on the
-- Stage root; the HUD, the world's popups and the card are hidden meanwhile.
local playStage: MicroStage.Stage? = nil
local playFrame: Frame? = nil

local function hideWorldUI(on: boolean)
	for _, name in { "Hud", "World" } do
		UIKit.root(name).Enabled = not on
	end
	-- the phone's thumbstick and jump button stay out of a microgame's way
	pcall(function()
		GuiService.TouchControlsEnabled = not on
	end)
	if shade then
		(shade :: TextButton).Visible = not on
	end
end

endPlay = function()
	local st = playStage
	playStage = nil
	if st then
		st.close()
	end
	local pf = playFrame
	playFrame = nil
	if pf then
		pf:Destroy()
	end
	hideWorldUI(false)
	PixelRenderer.setOffset(0, 0)
end

playSlot = function(slot: number, chain: boolean)
	local v = StateClient.view()
	local proj = if v then v.project else nil
	if proj == nil or mode == "play" then
		return
	end
	local card = (proj :: Types.Making).ideas[slot]
	local def = IdeasData.byId[card.id]
	local mod = Modifiers.byId[card.mod]
	if def == nil or mod == nil then
		return
	end
	mode = "play"
	local asked = os.clock()
	local res = StateClient.request("micro.start", { slot = slot })
	if not res.ok or type(res.data) ~= "table" then
		mode = "card"
		Audio.play("deny")
		UIKit.notice(Words.errText(res.err), UIKit.color("bad"))
		endPlay()
		showCard()
		return
	end
	local data = res.data :: { [string]: any }
	local token = tonumber(data.token) or 0
	local diff = math.clamp(tonumber(data.diff) or 1, 1, Tuning.DiffMax)
	ensureFrame()
	endPlay()
	hideWorldUI(true)
	local effects = mod.effects
	local tier = Ideas.tier(card)
	local canvas = UIKit.canvas("Stage")
	local size = UIKit.size("Stage")
	local w, h = size.X, size.Y
	local pf = Instance.new("Frame")
	pf.Name = "MicroPlay"
	pf.BackgroundTransparency = 1
	pf.BorderSizePixel = 0
	pf.Size = UDim2.fromOffset(w, h)
	pf.ZIndex = 1
	pf.Parent = canvas
	playFrame = pf
	local stage = MicroStage.open(def.variant)
	playStage = stage

	-- the engine's overlay: the whole screen (its UI px are the world's art px)
	local area = Instance.new("Frame")
	area.Name = "Area"
	area.BackgroundTransparency = 1
	area.BorderSizePixel = 0
	area.Size = UDim2.fromOffset(w, h)
	area.ZIndex = 2
	area.ClipsDescendants = true
	area.Parent = pf
	-- the header strip: the idea, its difficulty, its modifier
	local head = UIKit.rect(pf, UDim2.fromOffset(w, 22), UDim2.fromOffset(0, 0), UIKit.color("ink"), 5)
	head.Name = "Header"
	head.BackgroundTransparency = 0.2
	UIKit.rect(head, UDim2.fromOffset(w, 1), UDim2.fromOffset(0, 21), UIKit.color(Ideas.tierColor(tier)), 5)
	PixelSprites.image(head, "icon_" .. card.id, UDim2.fromOffset(4, 3), 6)
	UIKit.text(head, Ideas.name(card), UDim2.fromOffset(w - 120, 10), UDim2.fromOffset(24, 1), { color = UIKit.color(Ideas.tierColor(tier)), z = 6, name = "IdeaName" })
	UIKit.text(head, string.format("Idea %d of 3  Difficulty %d", slot, diff), UDim2.fromOffset(w - 120, 10), UDim2.fromOffset(24, 10), { color = UIKit.color("text_dim"), z = 6 })
	if mod.id ~= "plain" then
		local tw = UIKit.textWidth(mod.name) + 8
		UIKit.plate(head, UDim2.fromOffset(tw, 12), UDim2.fromOffset(w - tw - 4, 5), UIKit.color(mod.color), 0, 2).ZIndex = 6
		UIKit.text(head, mod.name, UDim2.fromOffset(tw, 12), UDim2.fromOffset(w - tw - 4, 5), { x = "center", color = UIKit.color("ink"), kind = "plain", z = 7, name = "ModTag" })
	end
	-- the bottom strip: the fuse (a rope with 1 px ink edges and a twist every 3 px, burning toward its bomb) and the hint
	local foot = UIKit.rect(pf, UDim2.fromOffset(w, 18), UDim2.fromOffset(0, h - 18), UIKit.color("ink"), 5)
	foot.Name = "Footer"
	foot.BackgroundTransparency = 0.2
	local bombW = PixelSprites.size("bombfuse")
	local ropeX, ropeY = 4 + bombW - 1, h - 15
	local ropeW = w - 4 - ropeX
	local bomb = PixelSprites.anim(pf, { "bombfuse" }, UDim2.fromOffset(4, h - 18), 7)
	bomb.f.Name = "FuseBomb"
	local fuse = Instance.new("Frame")
	fuse.Name = "Fuse"
	fuse.BackgroundTransparency = 1
	fuse.ClipsDescendants = true
	fuse.Size = UDim2.fromOffset(ropeW, 4)
	fuse.Position = UDim2.fromOffset(ropeX, ropeY)
	fuse.ZIndex = 6
	fuse.Parent = pf
	UIKit.rect(fuse, UDim2.fromOffset(ropeW, 1), UDim2.fromOffset(0, 0), UIKit.color("black"), 6).Name = "Edge"
	UIKit.rect(fuse, UDim2.fromOffset(ropeW, 1), UDim2.fromOffset(0, 3), UIKit.color("black"), 6).Name = "Edge"
	UIKit.rect(fuse, UDim2.fromOffset(ropeW, 2), UDim2.fromOffset(0, 1), UIKit.hex(0xEDC293), 6).Name = "Rope"
	for x = 1, ropeW - 2, 3 do
		UIKit.rect(fuse, UDim2.fromOffset(1, 1), UDim2.fromOffset(x, 1), UIKit.hex(0xC88D5C), 6).Name = "Twist"
		UIKit.rect(fuse, UDim2.fromOffset(1, 1), UDim2.fromOffset(x + 1, 2), UIKit.hex(0xC88D5C), 6).Name = "Twist"
	end
	local spark = PixelSprites.anim(pf, { "spark_1", "spark_2", "spark_3" }, UDim2.fromOffset(ropeX + ropeW - 4, ropeY - 2), 8)
	spark.f.Name = "Spark"
	local hintText = string.format('"%s"  %s', def.word, if #effects > 0 then mod.blurb else "")
	UIKit.text(pf, hintText, UDim2.fromOffset(w - 16, 10), UDim2.fromOffset(14, h - 10), { color = UIKit.color("text_dim"), z = 6, name = "Hint" })

	-- the effects: floating words, 1 px bits, floating sprites, the flash
	type Pop = { l: TextLabel, x: number, y: number, t0: number }
	local pops: { Pop } = {}
	type Bit = { f: Frame, x: number, y: number, vx: number, vy: number, t0: number, life: number }
	local bits: { Bit } = {}
	type Float = { g: GuiObject, x: number, y: number, vx: number, vy: number, grav: number, t0: number, life: number }
	local floats: { Float } = {}
	local fxRng = Util.newRng((tonumber(data.seed) or 1) + 101)
	local flashFrame = Instance.new("Frame")
	flashFrame.Name = "Flash"
	flashFrame.BackgroundColor3 = UIKit.color("white")
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Size = UDim2.fromScale(1, 1)
	flashFrame.ZIndex = 27
	flashFrame.Active = false
	flashFrame.Parent = area
	local flashUntil = 0
	local shakeUntil = 0
	local outcome: boolean? = nil
	local engine: Games.Micro? = nil
	local ctx: Games.Ctx = {
		area = area,
		w = w,
		h = h,
		stage = stage,
		rng = Util.newRng(tonumber(data.seed) or 1),
		diff = diff,
		speed = if has(effects, "speed") then Tuning.TurboSpeed else 1,
		tiny = has(effects, "tiny"),
		variant = def.variant,
		pop = function(x: number, y: number, text: string, color: Color3)
			local tw = UIKit.textWidth(text) + 4
			local l = UIKit.text(area, text, UDim2.fromOffset(tw, 10), UDim2.fromOffset(math.floor(x - tw / 2), math.floor(y)), { x = "center", color = color, kind = "outline", z = 30, name = "Pop" })
			table.insert(pops, { l = l, x = math.floor(x - tw / 2), y = math.floor(y), t0 = os.clock() })
		end,
		burst = function(x: number, y: number, colors: { string }, n: number?)
			local count = n or 8
			for i = 1, count do
				local c = UIKit.color(colors[(i - 1) % #colors + 1])
				local r = UIKit.rect(area, UDim2.fromOffset(1, 1), UDim2.fromOffset(math.floor(x), math.floor(y)), c, 28)
				r.Name = "Bit"
				r.Active = false
				local a = (i / count) * math.pi * 2 + fxRng:next() * 0.8
				local sp = 30 + fxRng:next() * 45
				table.insert(bits, { f = r, x = x, y = y, vx = math.cos(a) * sp, vy = math.sin(a) * sp - 25, t0 = os.clock(), life = 0.3 + fxRng:next() * 0.25 })
			end
		end,
		float = function(g: GuiObject, vx: number, vy: number, life: number, grav: number?)
			local p = g.Position
			table.insert(floats, { g = g, x = p.X.Offset, y = p.Y.Offset, vx = vx, vy = vy, grav = grav or 0, t0 = os.clock(), life = life })
		end,
		flash = function(color: string)
			flashFrame.BackgroundColor3 = UIKit.color(color)
			flashUntil = os.clock() + 0.08
		end,
		shake = function()
			shakeUntil = os.clock() + 0.25
		end,
		win = function()
			if outcome == nil then
				outcome = true
			end
		end,
		lose = function()
			if outcome == nil then
				outcome = false
			end
		end,
		press = function(k: string)
			local e = engine
			if e and outcome == nil and live then
				e.key(k)
			end
		end,
	}
	local okE, built = pcall(function(): Games.Micro
		return (Games :: any)[def.micro](ctx)
	end)
	if not okE then
		warn("[MicroUI] " .. def.micro .. ": " .. tostring(built))
		built = { update = function() end, key = function() end, auto = function() end, survive = true }
	end
	engine = built :: Games.Micro
	local eng = engine :: Games.Micro
	playing, playingKind = eng, def.micro
	local base = math.max(Tuning.MicroSecondsMin, Tuning.MicroSeconds - Tuning.MicroSecondsStep * (diff - 1))
	local seconds = math.min(Tuning.MicroMaxSec - 10, base * (eng.clock or 1) * (if has(effects, "speed") then Tuning.TurboClock else 1))
	if eng.clock == 99 then
		seconds = Tuning.MicroMaxSec - 10 -- the song decides when it ends
	end
	lastCtx = { diff = diff, speed = ctx.speed, tiny = ctx.tiny, seconds = seconds, effects = effects, micro = def.micro, area = area }

	-- the modifiers' screen effects
	local dark: { Frame } = {}
	if has(effects, "dark") then
		for i = 1, 4 do
			local r = UIKit.rect(area, UDim2.fromOffset(1, 1), nil, UIKit.color("ink"), 25)
			r.Name = "Dark" .. i
			r.Active = false
			table.insert(dark, r)
		end
	end
	local glitchAt, glitchUntil = 0.6, 0
	local fx = Instance.new("Frame")
	fx.Name = "GlitchFlash"
	fx.BackgroundColor3 = UIKit.color("screen_code")
	fx.BackgroundTransparency = 1
	fx.BorderSizePixel = 0
	fx.Size = UDim2.fromScale(1, 1)
	fx.ZIndex = 26
	fx.Active = false
	fx.Parent = area

	-- the curtain: blinds of ink over the screen while the stage's picture is baked, the idea's icon and its order word
	-- on them; they open from the middle once the stage is ready and the word has shown for MicroIntro (the
	-- container's "Lifted" attribute turns true then)
	local curtain = Instance.new("Frame")
	curtain.Name = "Curtain"
	curtain.BackgroundTransparency = 1
	curtain.BorderSizePixel = 0
	curtain.Size = UDim2.fromScale(1, 1)
	curtain.ZIndex = 35
	curtain.Active = false
	curtain:SetAttribute("Lifted", false)
	curtain.Parent = pf
	local BLIND = 12
	local blinds: { Frame } = {}
	for y = 0, h - 1, BLIND do
		local band = UIKit.rect(curtain, UDim2.fromOffset(w, math.min(BLIND, h - y)), UDim2.fromOffset(0, y), UIKit.color("ink"), 35)
		band.Name = "Blind"
		UIKit.rect(band, UDim2.new(1, 0, 0, 1), UDim2.new(0, 0, 1, -1), UIKit.hex(0x3B3048), 35)
		table.insert(blinds, band)
	end
	-- the word drops in with a bounce, the icon over it
	local introIcon = PixelSprites.image(pf, "icon_" .. card.id, UDim2.fromOffset(math.floor(w / 2) - 8, math.floor(h / 2) - 60), 40)
	introIcon.Name = "WordIcon"
	local word = UIKit.text(pf, def.word, UDim2.fromOffset(w, 18), UDim2.fromOffset(0, math.floor(h / 2) - 40), { x = "center", face = "big", kind = "title", color = UIKit.color(Ideas.tierColor(math.max(2, tier))), z = 40, name = "Word" })
	UIKit.tween(introIcon, 0.16, { Position = UDim2.fromOffset(math.floor(w / 2) - 8, math.floor(h / 2) - 20) })
	UIKit.tween(word, 0.16, { Position = UDim2.fromOffset(0, math.floor(h / 2)) })
	task.delay(0.16, function()
		if word.Parent then
			UIKit.tween(introIcon, 0.1, { Position = UDim2.fromOffset(math.floor(w / 2) - 8, math.floor(h / 2) - 24) })
			UIKit.tween(word, 0.1, { Position = UDim2.fromOffset(0, math.floor(h / 2) - 4) })
		end
	end)
	local ready = UIKit.text(pf, "Get ready...", UDim2.fromOffset(w, 10), UDim2.fromOffset(0, math.floor(h / 2) + 18), { x = "center", color = UIKit.color("text_dim"), z = 40, name = "GetReady" })
	Audio.play("ding")
	local function openBlinds()
		curtain:SetAttribute("Lifted", true)
		local mid = #blinds / 2
		for i, band in blinds do
			local delay = math.abs(i - 0.5 - mid) * 0.018
			local y0 = band.Position.Y.Offset
			local bh = band.Size.Y.Offset
			task.delay(delay, function()
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

	live = false
	local unbind = bindKeys(function(k: string)
		if outcome == nil and mode == "play" and live then
			eng.key(k)
		end
	end)
	local opened = os.clock()
	local t0 = math.huge -- the clock's start (set when the curtain lifts)
	local last = 0
	local finished = false
	local wonAs = false
	local finishedAt = 0
	local conn: RBXScriptConnection? = nil
	local function finish(won: boolean)
		if finished then
			return
		end
		finished = true
		live = false
		wonAs = won
		finishedAt = os.clock()
		playing, playingKind = nil, nil
		unbind()
		-- the stamp drops in with a bounce (the stage and the effects keep moving under it)
		local sy = math.floor(h / 2) - 30
		local stamp = UIKit.text(pf, if won then "WIN!" else "LOSE", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, sy - 30), { x = "center", face = "big", kind = "title", color = if won then UIKit.color("good") else UIKit.color("bad"), z = 40, name = "Stamp" })
		UIKit.tween(stamp, 0.12, { Position = UDim2.fromOffset(0, sy + 4) })
		task.delay(0.12, function()
			if stamp.Parent then
				UIKit.tween(stamp, 0.1, { Position = UDim2.fromOffset(0, sy) })
			end
		end)
		ctx.flash(if won then "white" else "bad")
		spark.f.Visible = false
		local torso = stage.avatar.rig.parts.Torso
		local at = if torso then torso.Position else stage.at(0, 0, 2)
		if won then
			Audio.play("combo")
			Audio.play("cheer")
			UIKit.confetti(area, 30)
			stage.puff(at + Vector3.new(0, 2, 0), "confetti", 24)
			stage.puff(at + Vector3.new(0, 1, 0), "spark", 10)
		else
			Audio.play("sad")
			bomb.flash(0.2)
			stage.puff(at - Vector3.new(0, 1.5, 0), "dust", 12)
		end
		task.spawn(function()
			local wait = math.max(1.1, Tuning.MicroMinSec + 0.2 - (os.clock() - asked))
			task.wait(wait)
			local fin = StateClient.request("micro.finish", { token = token, won = if won then 1 else 0 })
			if shade == nil then
				endPlay()
				return
			end
			mode = "card"
			if not fin.ok then
				UIKit.notice(Words.errText(fin.err), UIKit.color("bad"))
			end
			-- the view lags a moment behind the answer: show the result now, then the card follows the view
			local pv = StateClient.view()
			local pp = if pv then pv.project else nil
			if fin.ok and pp and type(fin.data) == "table" then
				pp.won[slot] = if fin.data.won == true then 1 else math.max(pp.won[slot], 0)
			end
			local n = if chain and pp then nextUnplayed(pp, slot) else nil
			if n then
				playSlot(n, true)
			else
				endPlay()
				showCard()
			end
		end)
	end
	local fxLast = os.clock()
	local nextSpark = 0
	local lastTick = 4
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if pf.Parent == nil or area.Parent == nil then
			if conn then
				conn:Disconnect()
			end
			if not finished then
				-- closed mid-game (a finished one already let go: the next may be playing by now)
				unbind()
				playing, playingKind = nil, nil
			end
			return
		end
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
		local fdt = math.min(0.05, now - fxLast)
		fxLast = now
		for i = #bits, 1, -1 do
			local b = bits[i]
			if now - b.t0 > b.life or b.f.Parent == nil then
				b.f:Destroy()
				table.remove(bits, i)
			else
				b.vy += 160 * fdt
				b.x += b.vx * fdt
				b.y += b.vy * fdt
				b.f.Position = UDim2.fromOffset(math.floor(b.x + 0.5), math.floor(b.y + 0.5))
			end
		end
		for i = #floats, 1, -1 do
			local o = floats[i]
			if now - o.t0 > o.life or o.g.Parent == nil then
				o.g:Destroy()
				table.remove(floats, i)
			else
				o.vy += o.grav * fdt
				o.x += o.vx * fdt
				o.y += o.vy * fdt
				o.g.Position = UDim2.fromOffset(math.floor(o.x + 0.5), math.floor(o.y + 0.5))
			end
		end
		flashFrame.BackgroundTransparency = if now < flashUntil then 0.45 else 1
		-- the stage's bits and its ambient life
		pcall(function()
			stage.step(now - opened, fdt)
		end)
		if finished then
			-- the founder cheers or stumbles under the stamp
			local after = eng.after
			if after then
				local t = now - t0
				pcall(function()
					after(t, wonAs)
				end)
			end
			local _ = finishedAt
			PixelRenderer.setOffset(0, 0)
			area.Position = UDim2.fromOffset(0, 0)
			return
		end
		-- the curtain lifts once the stage is baked (or after a few seconds, whatever) and the word has shown
		if t0 == math.huge then
			if (stage.ready() and now - opened >= Tuning.MicroIntro) or now - opened > Tuning.MicroStageWait then
				t0 = now
				last = now
				live = true
				openBlinds()
				stage.lift()
				ready:Destroy()
				task.delay(0.35, function()
					if word.Parent then
						word:Destroy()
						introIcon:Destroy()
					end
				end)
			else
				-- the stage stands still behind the curtain, the founder in place
				pcall(function()
					eng.update(0, 0)
				end)
				return
			end
		end
		local t = now - t0
		local dt = math.min(0.1, now - last)
		last = now
		if outcome == nil then
			local ok, err = pcall(function()
				eng.update(t, dt)
			end)
			if not ok then
				warn("[MicroUI] " .. def.micro .. ": " .. tostring(err))
				outcome = false
			end
		end
		-- the fuse burns down to the bomb (it flashes when nearly there)
		local left = math.clamp(1 - t / seconds, 0, 1)
		local lw = math.floor(ropeW * left)
		fuse.Size = UDim2.fromOffset(lw, 4)
		spark.moveTo(ropeX + lw - 4, ropeY - 2)
		spark.set(math.floor(now * 16) + 1)
		-- the burning end spits sparks; the last seconds tick
		if now >= nextSpark and lw > 0 then
			nextSpark = now + 0.07
			ctx.burst(ropeX + lw - 1, ropeY + 1, { "yellow", "orange" }, 2)
		end
		if eng.clock ~= 99 then
			local leftSec = math.ceil(seconds - t)
			if leftSec <= 3 and leftSec >= 1 and leftSec < lastTick then
				lastTick = leftSec
				Audio.play("tick", { pitch = 1.2 + (3 - leftSec) * 0.15 })
				bomb.flash(0.12)
			end
		end
		if left < 0.25 and math.floor(now * 6) % 2 == 0 then
			bomb.flash(0.05)
		end
		-- the modifiers (a shake moves the stage's picture and the overlay together)
		local ox, oy = 0, 0
		if has(effects, "shake") then
			ox, oy = math.floor(math.sin(now * 37) * 2 + 0.5), math.floor(math.cos(now * 29) * 2 + 0.5)
		end
		if now < shakeUntil then
			ox += if math.floor(now * 40) % 2 == 0 then 2 else -2
		end
		area.Position = UDim2.fromOffset(ox, oy)
		PixelRenderer.setOffset(ox, oy)
		if has(effects, "glitch") then
			if t >= glitchAt then
				glitchUntil = t + 0.1 + 0.08 * ctx.rng:next()
				glitchAt = t + 0.55 + 0.4 * ctx.rng:next()
			end
			fx.BackgroundTransparency = if t < glitchUntil then 0 else 1
		end
		if #dark == 4 then
			local hw, hh = math.floor(w * 0.5), math.floor(h * 0.6)
			local cx = math.floor(w / 2 + math.cos(t * 1.3) * w * 0.28)
			local cy = math.floor(h / 2 + math.sin(t * 1.9) * h * 0.22)
			local x0, y0 = math.clamp(cx - hw // 2, 0, w), math.clamp(cy - hh // 2, 0, h)
			local x1, y1 = math.clamp(cx + hw // 2, 0, w), math.clamp(cy + hh // 2, 0, h)
			dark[1].Position, dark[1].Size = UDim2.fromOffset(0, 0), UDim2.fromOffset(w, y0)
			dark[2].Position, dark[2].Size = UDim2.fromOffset(0, y1), UDim2.fromOffset(w, h - y1)
			dark[3].Position, dark[3].Size = UDim2.fromOffset(0, y0), UDim2.fromOffset(x0, y1 - y0)
			dark[4].Position, dark[4].Size = UDim2.fromOffset(x1, y0), UDim2.fromOffset(w - x1, y1 - y0)
		end
		if outcome ~= nil then
			finish(outcome :: boolean)
		elseif t >= seconds then
			if eng.survive ~= true then
				-- the fuse reached the bomb
				ctx.burst(4 + bombW / 2, h - 16, { "orange", "yellow", "white" }, 14)
			end
			finish(eng.survive == true)
		end
	end)
end

------------------------------------------------------------------ the launch
function MicroUI.showLaunch(g: Types.Game)
	local f = ensureFrame()
	clearFrame(f)
	mode = "launch"
	local w, h = f.Size.X.Offset, f.Size.Y.Offset
	-- the title drops in with a bounce
	local title = UIKit.text(f, "Launched!", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, -14), { x = "center", face = "big", kind = "title", color = UIKit.color("accent"), z = 7, name = "Launched" })
	UIKit.tween(title, 0.14, { Position = UDim2.fromOffset(0, 13) })
	task.delay(0.14, function()
		if title.Parent then
			UIKit.tween(title, 0.1, { Position = UDim2.fromOffset(0, 10) })
		end
	end)
	UIKit.text(f, g.title, UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 32), { x = "center", color = UIKit.color("text"), z = 7, name = "GameTitle" })
	-- the three ideas pop up one after another, a star over each won one
	for i, c in g.ideas do
		local x = math.floor(w / 2 - 40 + (i - 1) * 28)
		local pl = UIKit.plate(f, UDim2.fromOffset(24, 24), UDim2.fromOffset(x, 62), UIKit.color("plate_light"), 0, 2)
		pl.ZIndex = 7
		pl.Visible = false
		PixelSprites.image(pl, "icon_" .. c.id, UDim2.fromOffset(4, 4), 8)
		task.delay(0.25 + (i - 1) * 0.15, function()
			if pl.Parent then
				pl.Visible = true
				UIKit.tween(pl, 0.12, { Position = UDim2.fromOffset(x, 44) })
				task.delay(0.12, function()
					if pl.Parent then
						UIKit.tween(pl, 0.08, { Position = UDim2.fromOffset(x, 46) })
						UIKit.burst(f, x + 12, 58, { "accent", "white" }, 8)
					end
				end)
				Audio.play("pop", { pitch = 0.9 + i * 0.1 })
			end
		end)
	end
	UIKit.text(f, string.format("%d of 3 minigames won: sales x%.2f", g.wins, 1 + Tuning.WinBoost * g.wins), UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 74), { x = "center", color = UIKit.color("good"), z = 7 })
	-- the income counts up to what the game earns
	local rateLabel = UIKit.text(f, Numbers.rate(0) .. " coins", UDim2.fromOffset(w, 18), UDim2.fromOffset(0, 88), { x = "center", face = "big", kind = "title", color = UIKit.color("good"), z = 7, name = "Rate" })
	task.spawn(function()
		task.wait(0.3)
		local t0 = os.clock()
		while rateLabel.Parent do
			local k = math.clamp((os.clock() - t0) / 0.8, 0, 1)
			local e = 1 - (1 - k) * (1 - k)
			UIKit.setText(rateLabel, Numbers.rate(g.rate * e) .. " coins")
			if k >= 1 then
				UIKit.burst(f, w / 2, 96, { "good", "accent", "white" }, 16)
				Audio.play("coins")
				break
			end
			task.wait()
		end
	end)
	UIKit.text(f, "It earns this for good, even while you make the next one.", UDim2.fromOffset(w - 12, 10), UDim2.fromOffset(6, 110), { x = "center", color = UIKit.color("text_dim"), z = 7 })
	local nice = UIKit.button(f, "Nice!", UDim2.fromOffset(60, 14), UDim2.new(0.5, -30, 1, -20), function()
		close()
		MicroUI.Launched:Fire(g)
	end, { name = "Nice", color = UIKit.color("button_ok") })
	nice.ZIndex = 7
	Audio.play(if g.wins == 3 then "rare_fanfare" else "fanfare")
	task.delay(0.15, function()
		if f.Parent then
			UIKit.confetti(f, if g.wins == 3 then 50 else 26)
		end
	end)
	local _ = h
end

------------------------------------------------------------------ API
-- The card for the game being made.
function MicroUI.open()
	if mode == "play" then
		return
	end
	UIKit.closePanel()
	local v = StateClient.view()
	if v == nil or v.project == nil then
		-- just made: the view with the project is on its way
		pendingOpen = os.clock() + 3
		return
	end
	showCard()
end

-- After a new view: the card follows it (not while a microgame or the launch card is up).
function MicroUI.refresh()
	if mode == "card" then
		showCard()
	elseif mode == nil and os.clock() < pendingOpen then
		local v = StateClient.view()
		if v and v.project then
			pendingOpen = 0
			showCard()
		end
	end
end

-- The engine of the microgame in play, or nil (the sims and the previews).
function MicroUI.playing(): string?
	return playingKind
end

-- One right move in the microgame in play (the sims' and the previews' player).
function MicroUI.debugAuto()
	local e = playing
	if e and live then
		e.auto()
	end
end

-- The last microgame's settings: diff, speed, tiny, seconds, effects, micro, area (the sims).
function MicroUI.debugCtx(): { [string]: any }?
	return lastCtx
end

-- Play a slot from code (the sims and the previews), as the card's Play button does.
function MicroUI.play(slot: number, chain: boolean?)
	playSlot(slot, chain == true)
end

function MicroUI.init() end

return MicroUI
